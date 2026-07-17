#!/usr/bin/swift
import CryptoKit
import Darwin
import Foundation
import Security

private struct Plan: Decodable {
    struct Test: Decodable {
        let id: String
    }

    let schemaVersion: Int
    let tests: [Test]
}

private struct RecordedResult: Decodable {
    let id: String
    let passed: Bool
}

private struct UnsignedAttestation: Encodable {
    let schemaVersion: Int
    let nonce: UUID
    let issuedAt: Date
    let sourceCommit: String
    let appBundleIdentifier: String
    let appVersion: String
    let appBuild: String
    let appDesignatedRequirementHash: String
    let runtimeVersion: String
    let runtimePackageSHA256: String
    let testPlanVersion: String
    let hostModel: String
    let macOSBuild: String
    let operationResults: [String: Bool]
    let residueCount: Int
    let baselineRestored: Bool
    let cleanupLedgerEmpty: Bool
    let signerKeyID: String
    let signature: String
}

private struct ApplicationIdentity {
    let bundleIdentifier: String
    let version: String
    let build: String
    let designatedRequirementHash: String
}

private struct AttestationExpectations: Encodable {
    let sourceCommit: String
    let appBundleIdentifier: String
    let appVersion: String
    let appBuild: String
    let appDesignatedRequirementHash: String
    let runtimeVersion: String
    let runtimePackageSHA256: String
    let testPlanVersion: String
    let requiredOperationIDs: [String]
    let verificationNow: Date
    let maximumAge: TimeInterval
    let futureTolerance: TimeInterval
}

private enum SummaryError: Error, CustomStringConvertible {
    case usage
    case invalidPlan
    case invalidResults
    case incompleteResults
    case invalidApplication
    case invalidIdentity

    var description: String {
        switch self {
        case .usage: "invalid arguments"
        case .invalidPlan: "invalid physical test plan"
        case .invalidResults: "invalid physical result files"
        case .incompleteResults: "physical result set does not exactly cover the test plan"
        case .invalidApplication: "invalid signed application bundle"
        case .invalidIdentity: "invalid attestation identity"
        }
    }
}

private func argument(_ name: String, in arguments: [String]) throws -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        throw SummaryError.usage
    }
    return arguments[index + 1]
}

private func strictBool(_ value: String) throws -> Bool {
    switch value {
    case "true": true
    case "false": false
    default: throw SummaryError.usage
    }
}

private func commandOutput(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw SummaryError.invalidIdentity }
    guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
        throw SummaryError.invalidIdentity
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func designatedRequirementHash(for application: URL) throws -> String {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(application as CFURL, [], &staticCode) == errSecSuccess,
          let staticCode
    else {
        throw SummaryError.invalidApplication
    }
    guard SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else {
        throw SummaryError.invalidApplication
    }
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
          let requirement
    else {
        throw SummaryError.invalidApplication
    }
    var requirementString: CFString?
    guard SecRequirementCopyString(requirement, [], &requirementString) == errSecSuccess,
          let requirementString
    else {
        throw SummaryError.invalidApplication
    }
    let digest = SHA256.hash(data: Data((requirementString as String).utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func loadApplicationIdentity(_ application: URL) throws -> ApplicationIdentity {
    let infoURL = application.appendingPathComponent("Contents/Info.plist")
    guard let info = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: infoURL),
        format: nil
    ) as? [String: Any],
        let identifier = info["CFBundleIdentifier"] as? String,
        identifier == "container.matrixreligio.com",
        let version = info["CFBundleShortVersionString"] as? String,
        !version.isEmpty,
        let build = info["CFBundleVersion"] as? String,
        !build.isEmpty
    else {
        throw SummaryError.invalidApplication
    }
    return try ApplicationIdentity(
        bundleIdentifier: identifier,
        version: version,
        build: build,
        designatedRequirementHash: designatedRequirementHash(for: application)
    )
}

private func loadResults(at directory: URL, requiredIDs: Set<String>) throws -> [String: Bool] {
    let manager = FileManager.default
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    let entries = try manager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: Array(keys),
        options: []
    )
    guard !entries.isEmpty else { throw SummaryError.incompleteResults }
    var results: [String: Bool] = [:]
    for entry in entries {
        let values = try entry.resourceValues(forKeys: keys)
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              entry.pathExtension == "json"
        else {
            throw SummaryError.invalidResults
        }
        let result = try JSONDecoder().decode(RecordedResult.self, from: Data(contentsOf: entry))
        guard requiredIDs.contains(result.id), results.updateValue(result.passed, forKey: result.id) == nil else {
            throw SummaryError.invalidResults
        }
    }
    guard Set(results.keys) == requiredIDs, results.values.allSatisfy(\.self) else {
        throw SummaryError.incompleteResults
    }
    return results
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let expectedNames: Set = [
        "--plan", "--results", "--app", "--output", "--source-commit", "--runtime-version",
        "--runtime-sha256", "--signer-key-id", "--residue-count", "--baseline-restored",
        "--cleanup-ledger-empty"
    ]
    guard arguments.count == expectedNames.count * 2,
          Set(arguments.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }) == expectedNames
    else {
        throw SummaryError.usage
    }

    let output = try URL(fileURLWithPath: argument("--output", in: arguments)).standardizedFileURL
    let expectationsOutput = output.deletingPathExtension().appendingPathExtension("expectations.json")
    try? FileManager.default.removeItem(at: output)
    try? FileManager.default.removeItem(at: expectationsOutput)
    let plan = try JSONDecoder().decode(
        Plan.self,
        from: Data(contentsOf: URL(fileURLWithPath: argument("--plan", in: arguments)))
    )
    let testIDs = plan.tests.map(\.id)
    guard plan.schemaVersion == 1,
          !testIDs.isEmpty,
          Set(testIDs).count == testIDs.count,
          testIDs.allSatisfy({ !$0.isEmpty })
    else {
        throw SummaryError.invalidPlan
    }

    let sourceCommit = try argument("--source-commit", in: arguments)
    let runtimeSHA256 = try argument("--runtime-sha256", in: arguments)
    let signerKeyID = try argument("--signer-key-id", in: arguments)
    guard sourceCommit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
          runtimeSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
          !signerKeyID.isEmpty,
          let residueCount = try Int(argument("--residue-count", in: arguments)),
          residueCount >= 0
    else {
        throw SummaryError.invalidIdentity
    }

    let application = try URL(fileURLWithPath: argument("--app", in: arguments), isDirectory: true)
        .standardizedFileURL
    let identity = try loadApplicationIdentity(application)
    let results = try loadResults(
        at: URL(fileURLWithPath: argument("--results", in: arguments), isDirectory: true),
        requiredIDs: Set(testIDs)
    )
    let summary = try UnsignedAttestation(
        schemaVersion: 1,
        nonce: UUID(),
        issuedAt: Date(),
        sourceCommit: sourceCommit,
        appBundleIdentifier: identity.bundleIdentifier,
        appVersion: identity.version,
        appBuild: identity.build,
        appDesignatedRequirementHash: identity.designatedRequirementHash,
        runtimeVersion: argument("--runtime-version", in: arguments),
        runtimePackageSHA256: runtimeSHA256,
        testPlanVersion: "physical-v\(plan.schemaVersion)",
        hostModel: commandOutput("/usr/sbin/sysctl", ["-n", "hw.model"]),
        macOSBuild: commandOutput("/usr/bin/sw_vers", ["-buildVersion"]),
        operationResults: results,
        residueCount: residueCount,
        baselineRestored: strictBool(argument("--baseline-restored", in: arguments)),
        cleanupLedgerEmpty: strictBool(argument("--cleanup-ledger-empty", in: arguments)),
        signerKeyID: signerKeyID,
        signature: ""
    )
    guard summary.baselineRestored, summary.cleanupLedgerEmpty, summary.residueCount == 0 else {
        throw SummaryError.incompleteResults
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(summary).write(to: output, options: [.atomic])
    let expectations = AttestationExpectations(
        sourceCommit: summary.sourceCommit,
        appBundleIdentifier: summary.appBundleIdentifier,
        appVersion: summary.appVersion,
        appBuild: summary.appBuild,
        appDesignatedRequirementHash: summary.appDesignatedRequirementHash,
        runtimeVersion: summary.runtimeVersion,
        runtimePackageSHA256: summary.runtimePackageSHA256,
        testPlanVersion: summary.testPlanVersion,
        requiredOperationIDs: results.keys.sorted(),
        verificationNow: summary.issuedAt,
        maximumAge: 366 * 24 * 60 * 60,
        futureTolerance: 300
    )
    try encoder.encode(expectations).write(to: expectationsOutput, options: [.atomic])
    print("PHYSICAL_SUMMARY_PASS: \(results.count) exact operations")
} catch {
    FileHandle.standardError.write(Data("physical summary error: \(error)\n".utf8))
    exit(65)
}

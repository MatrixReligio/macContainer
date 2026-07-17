import Foundation
import MCSystemLifecycle

@main
enum MCPhysicalTool {
    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            throw UsageError()
        }
        arguments.removeFirst()

        switch command {
        case "preflight":
            try await preflight(arguments)
        case "compare-baseline":
            try compareBaseline(arguments)
        case "recover":
            try await recover(arguments)
        case "ledger-transition":
            try await ledgerTransition(arguments)
        case "assert-no-active-ledger":
            try await assertNoActiveLedger(arguments)
        case "simulate-run":
            try await PhysicalSimulation.run(arguments)
        default:
            throw UsageError()
        }
    }

    private static func preflight(_ arguments: [String]) async throws {
        guard arguments.count == 2, arguments[0] == "--output" else {
            throw UsageError()
        }
        let outputURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let result = try await PhysicalPreflight(environment: SystemPhysicalPreflightEnvironment()).run()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result.baseline)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: outputURL, options: [.atomic])

        switch result.permission {
        case .safeToTest:
            print("SAFE_TO_TEST")
        case .refusedExistingState:
            print("REFUSED_EXISTING_STATE: \(result.refusalReasons.joined(separator: ","))")
            Foundation.exit(2)
        }
    }

    private static func compareBaseline(_ arguments: [String]) throws {
        guard arguments.count == 2 else { throw UsageError() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(
            MachineBaseline.self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[0]))
        )
        let second = try decoder.decode(
            MachineBaseline.self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        )
        guard first.canonicalForComparison == second.canonicalForComparison else {
            print("BASELINE_MISMATCH")
            Foundation.exit(3)
        }
        print("BASELINE_MATCH")
    }

    private static func recover(_ arguments: [String]) async throws {
        guard
            arguments.count == 4,
            arguments[0] == "--run-root",
            arguments[2] == "--run-id",
            let runID = UUID(uuidString: arguments[3])
        else {
            throw UsageError()
        }
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        let ledgerURL = root.appendingPathComponent("cleanup.jsonl")
        let storage = try FileCleanupLedgerStorage(url: ledgerURL)
        let ledger = try await CleanupLedger.recover(storage: storage, runID: runID)
        let policy = PhysicalCleanupPolicy(runID: runID, runRoot: root)
        let cleanup = GuardedCleanup(policy: policy, ledger: ledger)
        try await GuardedCleanupRecovery(
            policy: policy,
            ledger: ledger,
            cleanup: cleanup,
            ledgerURL: ledgerURL
        ).run()
        print("RECOVERY_PASS: cleanup ledger contains only verifiedAbsent states")
    }

    private static func ledgerTransition(_ arguments: [String]) async throws {
        guard
            arguments.count == 10,
            arguments[0] == "--run-root",
            arguments[2] == "--run-id",
            let runID = UUID(uuidString: arguments[3]),
            arguments[4] == "--type",
            arguments[6] == "--value",
            arguments[8] == "--state"
        else {
            throw UsageError()
        }
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        let artifact = try artifact(type: arguments[5], value: arguments[7])
        try PhysicalCleanupPolicy(runID: runID, runRoot: root).validate(artifact)
        let storage = try FileCleanupLedgerStorage(url: root.appendingPathComponent("cleanup.jsonl"))
        let ledger = try await CleanupLedger.recover(storage: storage, runID: runID)
        switch arguments[9] {
        case "planned":
            try await ledger.plan(artifact)
        case "created":
            try await ledger.markCreated(artifact)
        default:
            throw UsageError()
        }
    }

    private static func artifact(type: String, value: String) throws -> TestArtifact {
        switch type {
        case "file": return .file(value)
        case "temporary-directory": return .temporaryDirectory(value)
        case "runtime-package": return .runtimePackage(value)
        case "result-bundle": return .resultBundle(value)
        case "launch-service": return .launchService(value)
        case "container": return .container(value)
        case "image": return .image(value)
        case "network": return .network(value)
        case "volume": return .volume(value)
        case "machine": return .machine(value)
        case "registry-credential": return .registryCredential(value)
        case "resolver": return .resolver(value)
        case "packet-filter-anchor": return .packetFilterAnchor(value)
        case "rollback-point":
            guard let identifier = UUID(uuidString: value) else { throw UsageError() }
            return .rollbackPoint(identifier)
        default:
            throw UsageError()
        }
    }

    private static func assertNoActiveLedger(_ arguments: [String]) async throws {
        guard arguments.count == 1 else { throw UsageError() }
        let root = URL(fileURLWithPath: arguments[0], isDirectory: true).standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else {
            print("NO_ACTIVE_LEDGER")
            return
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw CleanupPolicyError.absenceVerificationFailed
        }
        var ledgerCount = 0
        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent == "cleanup.jsonl" else { continue }
            ledgerCount += 1
            let storage = try FileCleanupLedgerStorage(url: url)
            let events = try await storage.load()
            guard !events.isEmpty else { throw CleanupLedgerError.corruptLedger }
            let latest = Dictionary(grouping: events, by: \.artifact).compactMapValues(\.last?.state)
            guard latest.values.allSatisfy({ $0 == .verifiedAbsent }) else {
                throw CleanupPolicyError.absenceVerificationFailed
            }
        }
        print("NO_ACTIVE_LEDGER: \(ledgerCount) completed ledger(s)")
    }
}

private struct UsageError: Error, CustomStringConvertible {
    var description: String {
        "usage: mc-physical preflight --output <path> | compare-baseline <before> <after> | " +
            "recover --run-root <path> --run-id <uuid> | ledger-transition --run-root <path> " +
            "--run-id <uuid> --type <type> --value <value> --state <planned|created> | " +
            "assert-no-active-ledger <physical-root> | simulate-run --run-root <path> --run-id <uuid> --plan <path>"
    }
}

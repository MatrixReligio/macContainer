#!/usr/bin/swift

import Darwin
import Foundation

struct Contract: Decodable {
    let runtimeVersion: RuntimeVersion
    let sourceCommit: String
    let operations: [ContractOperation]
}

struct RuntimeVersion: Decodable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String {
        "\(major).\(minor).\(patch)"
    }
}

struct ContractOperation: Decodable {
    let id: String
}

struct BridgeMap: Decodable {
    let schemaVersion: Int
    let runtimeVersion: String
    let sourceCommit: String
    let entries: [BridgeEntry]
}

struct BridgeEntry: Decodable {
    let operationID: String
    let appProtocolMethod: String
    let productionAdapterType: String
    let upstreamAction: String
    let focusedTest: String
    let cancellationBehavior: String
    let lockKey: String
    let backend: String
}

let allowedBackends: Set<String> = [
    "directSwiftAPI",
    "directXPC",
    "Security.framework",
    "nativeServiceManagement"
]
let allowedCancellationBehaviors: Set<String> = [
    "cancelsBackendStream",
    "checksCancellationBetweenBatchItems",
    "propagatesTaskCancellation",
    "propagatesTaskCancellationAndCleansTemporaryFiles",
    "propagatesTaskCancellationWithOwnedServiceCleanup",
    "rollsBackPartialMutation",
    "uncancelledRollbackThenRethrow"
]
let allowedLockKeys: Set<String> = [
    "builder",
    "container(resourceID)",
    "image(resourceID)",
    "lifecycle",
    "lifecycleForSaveApply",
    "machine(resourceID)",
    "network(resourceID)",
    "none",
    "registry(resourceID)",
    "systemService",
    "volume(resourceID)"
]

func fail(_ messages: [String]) -> Never {
    let output = messages.sorted().map { "Bridge coverage FAIL: \($0)" }.joined(separator: "\n") + "\n"
    FileHandle.standardError.write(Data(output.utf8))
    exit(EXIT_FAILURE)
}

func duplicates(_ values: [String]) -> [String] {
    Dictionary(grouping: values, by: { $0 })
        .filter { $0.value.count > 1 }
        .map(\.key)
        .sorted()
}

func sourceText(at root: URL) throws -> String {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return ""
    }

    var result = ""
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        result += try String(contentsOf: url, encoding: .utf8)
        result += "\n"
    }
    return result
}

guard CommandLine.arguments.count == 3 else {
    fail(["usage: swift scripts/check-bridge-coverage.swift <contract.json> <bridge-map.json>"])
}

let fileManager = FileManager.default
let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let contractURL = URL(fileURLWithPath: CommandLine.arguments[1], relativeTo: repositoryRoot).standardizedFileURL
let mapURL = URL(fileURLWithPath: CommandLine.arguments[2], relativeTo: repositoryRoot).standardizedFileURL
let decoder = JSONDecoder()
let contract: Contract
let map: BridgeMap
do {
    contract = try decoder.decode(Contract.self, from: Data(contentsOf: contractURL))
    map = try decoder.decode(BridgeMap.self, from: Data(contentsOf: mapURL))
} catch {
    fail(["could not decode reviewed inputs: \(error)"])
}

var errors: [String] = []
let operationIDs = contract.operations.map(\.id)
let mappedIDs = map.entries.map(\.operationID)
let duplicateOperationIDs = duplicates(mappedIDs)
let contractSet = Set(operationIDs)
let mappedSet = Set(mappedIDs)

if map.schemaVersion != 1 {
    errors.append("bridge map schema version must be 1")
}

if map.runtimeVersion != contract.runtimeVersion.description || map.runtimeVersion != "1.1.0" {
    errors.append("bridge map runtime does not match reviewed apple/container 1.1.0")
}

if map.sourceCommit != contract.sourceCommit {
    errors.append("bridge map source commit does not match the bundled contract")
}

if contract.operations.count != 61 || map.entries.count != 61 {
    errors.append("expected 61 contract operations and 61 bridge entries")
}

if mappedIDs != operationIDs {
    errors.append("bridge entries must preserve reviewed contract order")
}

if !duplicateOperationIDs.isEmpty {
    errors.append("duplicate mappings: \(duplicateOperationIDs.joined(separator: ", "))")
}

let missing = contractSet.subtracting(mappedSet).sorted()
let extra = mappedSet.subtracting(contractSet).sorted()
if !missing.isEmpty {
    errors.append("missing mappings: \(missing.joined(separator: ", "))")
}

if !extra.isEmpty {
    errors.append("unknown mappings: \(extra.joined(separator: ", "))")
}

let sources: String
do {
    sources = try sourceText(at: repositoryRoot.appendingPathComponent("Sources", isDirectory: true))
} catch {
    fail(["could not read production sources: \(error)"])
}

for entry in map.entries {
    if !allowedBackends.contains(entry.backend) {
        errors.append("\(entry.operationID) uses forbidden or unknown backend \(entry.backend)")
    }
    if !allowedCancellationBehaviors.contains(entry.cancellationBehavior) {
        errors.append("\(entry.operationID) has unknown cancellation behavior")
    }
    if !allowedLockKeys.contains(entry.lockKey) {
        errors.append("\(entry.operationID) has unknown lock key \(entry.lockKey)")
    }
    if entry.appProtocolMethod.isEmpty || entry.upstreamAction.isEmpty {
        errors.append("\(entry.operationID) has incomplete direct action metadata")
    }

    let backendClaim = [entry.backend, entry.productionAdapterType, entry.upstreamAction]
        .joined(separator: " ")
        .lowercased()
    if ["commandline", "process", "shell"].contains(where: backendClaim.contains) {
        errors.append("\(entry.operationID) names a command-line backend")
    }

    let hasAdapter = sources.contains("struct \(entry.productionAdapterType)")
        || sources.contains("class \(entry.productionAdapterType)")
        || sources.contains("actor \(entry.productionAdapterType)")
    if !hasAdapter {
        errors.append("\(entry.operationID) adapter type is absent from production sources")
    }

    let testParts = entry.focusedTest.split(separator: "#", maxSplits: 1).map(String.init)
    guard testParts.count == 2, testParts.allSatisfy({ !$0.isEmpty }) else {
        errors.append("\(entry.operationID) has an invalid focused test reference")
        continue
    }
    let testURL = repositoryRoot.appendingPathComponent(testParts[0]).standardizedFileURL
    guard testURL.path.hasPrefix(repositoryRoot.path + "/"), fileManager.fileExists(atPath: testURL.path) else {
        errors.append("\(entry.operationID) focused test file is missing")
        continue
    }
    do {
        let testSource = try String(contentsOf: testURL, encoding: .utf8)
        if !testSource.contains(testParts[1]) {
            errors.append("\(entry.operationID) focused test name is missing")
        }
    } catch {
        errors.append("\(entry.operationID) focused test could not be read")
    }
}

if !errors.isEmpty {
    fail(errors)
}

print("Bridge coverage PASS: 61 operations, 61 direct mappings, 0 CLI backends")

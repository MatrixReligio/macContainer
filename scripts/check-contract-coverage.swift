#!/usr/bin/swift

import Darwin
import Foundation

struct RuntimeVersion: Decodable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String {
        "\(major).\(minor).\(patch)"
    }
}

struct Acceptance: Decodable {
    let schemaVersion: Int
    let upstreamRepository: String
    let sourceTag: String
    let sourceCommit: String
    let commandReference: String
    let expectedOperationCount: Int
    let sharedParameterSources: [String]
    let operations: [AcceptedOperation]
}

struct AcceptedOperation: Decodable {
    let id: String
    let sourcePath: String
    let parameterIDs: [String]
}

struct Contract: Decodable {
    let schemaVersion: Int
    let runtimeVersion: RuntimeVersion
    let sourceCommit: String
    let operations: [ContractOperation]
}

struct ContractOperation: Decodable {
    let id: String
    let domain: String
    let nativeAction: String
    let risk: String
    let parameters: [ContractParameter]
}

struct ContractParameter: Decodable {
    let id: String
    let cliNames: [String]
    let valueType: String
    let acceptedValues: [String]
    let grammar: String?
    let availability: Availability
    let labelKey: String
    let conciseHelpKey: String
    let detailedHelpKey: String
    let validationErrorKey: String
    let recoveryKey: String
}

struct Availability: Decodable {
    let minimumRuntime: RuntimeVersion
    let minimumMacOSMajor: Int
    let requiresAppleSilicon: Bool
    let requiredCapabilities: [String]
}

func fail(_ messages: [String]) -> Never {
    let output = (messages.map { "Contract coverage FAIL: \($0)" }.joined(separator: "\n") + "\n")
    FileHandle.standardError.write(Data(output.utf8))
    exit(EXIT_FAILURE)
}

func duplicates(_ values: [String]) -> [String] {
    Dictionary(grouping: values, by: { $0 })
        .filter { $0.value.count > 1 }
        .map(\.key)
        .sorted()
}

func difference(_ lhs: Set<String>, _ rhs: Set<String>) -> [String] {
    Array(lhs.subtracting(rhs)).sorted()
}

guard CommandLine.arguments.count == 3 else {
    fail(["usage: swift scripts/check-contract-coverage.swift <acceptance.json> <contract.json>"])
}

let decoder = JSONDecoder()
let acceptanceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let contractURL = URL(fileURLWithPath: CommandLine.arguments[2])

let acceptance: Acceptance
let contract: Contract
do {
    acceptance = try decoder.decode(Acceptance.self, from: Data(contentsOf: acceptanceURL))
    contract = try decoder.decode(Contract.self, from: Data(contentsOf: contractURL))
} catch {
    fail(["could not decode reviewed inputs: \(error)"])
}

var errors: [String] = []
let expectedVersion = RuntimeVersion(major: 1, minor: 1, patch: 0)

if acceptance.schemaVersion != 1 || contract.schemaVersion != 1 {
    errors.append("schema version must be 1 in both inputs")
}

if acceptance.upstreamRepository != "https://github.com/apple/container" {
    errors.append("unexpected upstream repository \(acceptance.upstreamRepository)")
}

if acceptance.sourceTag != expectedVersion.description || contract.runtimeVersion != expectedVersion {
    errors.append("runtime identity must be apple/container \(expectedVersion)")
}

if acceptance.sourceCommit != contract.sourceCommit {
    errors.append("source commit differs between acceptance matrix and bundled contract")
}

if acceptance.sourceCommit != "5973b9cc626a3e7a499bb316a958237ebe14e2ed" {
    errors.append("source commit is not the reviewed 1.1.0 tag commit")
}

if acceptance.commandReference != "docs/command-reference.md" {
    errors.append("unexpected command reference \(acceptance.commandReference)")
}

if acceptance.expectedOperationCount != 61 {
    errors.append("acceptance matrix must declare the reviewed 61-operation count")
}

if acceptance.sharedParameterSources.isEmpty {
    errors.append("shared parameter source list is empty")
}

let acceptedIDs = acceptance.operations.map(\.id)
let contractIDs = contract.operations.map(\.id)
let duplicateAcceptedIDs = duplicates(acceptedIDs)
let duplicateContractIDs = duplicates(contractIDs)
if !duplicateAcceptedIDs.isEmpty {
    errors.append("duplicate acceptance operation IDs: \(duplicateAcceptedIDs.joined(separator: ", "))")
}

if !duplicateContractIDs.isEmpty {
    errors.append("duplicate contract operation IDs: \(duplicateContractIDs.joined(separator: ", "))")
}

if acceptance.operations.count != acceptance.expectedOperationCount {
    errors.append(
        "acceptance operation count is \(acceptance.operations.count), " +
            "expected \(acceptance.expectedOperationCount)"
    )
}

if contract.operations.count != acceptance.expectedOperationCount {
    errors.append(
        "contract operation count is \(contract.operations.count), " +
            "expected \(acceptance.expectedOperationCount)"
    )
}

let acceptedSet = Set(acceptedIDs)
let contractSet = Set(contractIDs)
let missingOperations = difference(acceptedSet, contractSet)
let extraOperations = difference(contractSet, acceptedSet)
if !missingOperations.isEmpty {
    errors.append("missing operation IDs: \(missingOperations.joined(separator: ", "))")
}

if !extraOperations.isEmpty {
    errors.append("extra operation IDs: \(extraOperations.joined(separator: ", "))")
}

let acceptedByID = Dictionary(uniqueKeysWithValues: acceptance.operations.map { ($0.id, $0) })
for accepted in acceptance.operations {
    if !accepted.sourcePath.hasPrefix("Sources/") || !accepted.sourcePath.hasSuffix(".swift") {
        errors.append("\(accepted.id) has invalid upstream source path \(accepted.sourcePath)")
    }
    let duplicateParameters = duplicates(accepted.parameterIDs)
    if !duplicateParameters.isEmpty {
        errors.append("\(accepted.id) has duplicate acceptance parameter IDs: \(duplicateParameters.joined(separator: ", "))")
    }
}

let metadataFields: [(ContractParameter) -> String] = [
    { $0.labelKey },
    { $0.conciseHelpKey },
    { $0.detailedHelpKey },
    { $0.validationErrorKey },
    { $0.recoveryKey }
]

for operation in contract.operations {
    if operation.domain.isEmpty || operation.nativeAction.isEmpty || operation.risk.isEmpty {
        errors.append("\(operation.id) has incomplete operation metadata")
    }

    let parameterIDs = operation.parameters.map(\.id)
    let duplicateParameters = duplicates(parameterIDs)
    if !duplicateParameters.isEmpty {
        errors.append("\(operation.id) has duplicate contract parameter IDs: \(duplicateParameters.joined(separator: ", "))")
    }

    if let accepted = acceptedByID[operation.id] {
        let expected = Set(accepted.parameterIDs)
        let actual = Set(parameterIDs)
        let missing = difference(expected, actual)
        let extra = difference(actual, expected)
        if !missing.isEmpty {
            errors.append("\(operation.id) missing parameter IDs: \(missing.joined(separator: ", "))")
        }
        if !extra.isEmpty {
            errors.append("\(operation.id) extra parameter IDs: \(extra.joined(separator: ", "))")
        }
    }

    for parameter in operation.parameters {
        if parameter.cliNames.isEmpty {
            errors.append("\(operation.id).\(parameter.id) has no upstream/native input name")
        }
        if metadataFields.contains(where: { $0(parameter).isEmpty }) {
            errors.append("\(operation.id).\(parameter.id) has an empty localization/help key")
        }
        if parameter.valueType != "boolean" && parameter.acceptedValues.isEmpty && parameter.grammar == nil {
            errors.append("\(operation.id).\(parameter.id) has neither accepted values nor grammar")
        }
        let hasInconsistentAvailability = parameter.availability.minimumRuntime != expectedVersion
            || parameter.availability.minimumMacOSMajor != 26
            || !parameter.availability.requiresAppleSilicon
            || !parameter.availability.requiredCapabilities.contains(operation.id)
        if hasInconsistentAvailability {
            errors.append("\(operation.id).\(parameter.id) has inconsistent availability metadata")
        }
    }
}

if !errors.isEmpty {
    fail(errors.sorted())
}

print("Contract coverage PASS: apple/container 1.1.0, 61 operations, 0 missing, 0 extra")

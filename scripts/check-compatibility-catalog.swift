#!/usr/bin/swift

import Darwin
import Foundation

private struct Catalog: Decodable {
    let schemaVersion: Int
    let revision: String
    let entries: [Entry]
    let updateURL: URL?
}

private struct Entry: Decodable {
    let runtimeVersion: String
    let package: PackageIdentity
    let adapterPackageVersion: String
    let capabilityIDs: Set<String>
    let requiredProbeIDs: [String]
    let attestation: Attestation
}

private struct PackageIdentity: Decodable, Equatable {
    let runtimeVersion: String
    let assetName: String
    let sha256: String
    let installerTeamID: String
    let signerCommonName: String
    let receiptIdentifier: String
}

private struct PackageManifest: Decodable {
    let runtimeVersion: String
    let assetName: String
    let sha256: String
    let installerTeamID: String
    let signerCommonName: String
    let receiptIdentifier: String
}

private struct Attestation: Decodable {
    let id: String
    let source: String
}

private struct Contract: Decodable {
    let operations: [Operation]
}

private struct Operation: Decodable {
    let id: String
}

private func fail(_ messages: [String]) -> Never {
    let output = messages.map { "Compatibility catalog FAIL: \($0)" }.joined(separator: "\n") + "\n"
    FileHandle.standardError.write(Data(output.utf8))
    exit(EXIT_FAILURE)
}

guard CommandLine.arguments.count == 2 else {
    fail(["usage: swift scripts/check-compatibility-catalog.swift <catalog-v1.json>"])
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1], relativeTo: root).standardizedFileURL
let embeddedURL = root.appending(path: "Sources/MCCompatibility/Resources/catalog-v1.json")
let packageURL = root.appending(path: "Config/compatibility/apple-container-1.1.0-package.json")
let contractURL = root.appending(path: "Sources/MCContracts/Resources/apple-container-1.1.0.json")

let catalogData: Data
let embeddedData: Data
private let catalog: Catalog
private let package: PackageManifest
private let contract: Contract
do {
    catalogData = try Data(contentsOf: catalogURL)
    embeddedData = try Data(contentsOf: embeddedURL)
    let decoder = JSONDecoder()
    catalog = try decoder.decode(Catalog.self, from: catalogData)
    package = try decoder.decode(PackageManifest.self, from: Data(contentsOf: packageURL))
    contract = try decoder.decode(Contract.self, from: Data(contentsOf: contractURL))
} catch {
    fail(["could not decode reviewed inputs: \(error)"])
}

var errors: [String] = []
if catalogData != embeddedData {
    errors.append("Config catalog differs from the embedded signed resource")
}

if catalog.schemaVersion != 1 || catalog.revision.isEmpty {
    errors.append("schema version and revision must identify catalog v1")
}

if catalog.updateURL != nil {
    errors.append("remote catalog authority is forbidden")
}

if catalog.entries.count != 1 || catalog.entries.first?.runtimeVersion != "1.1.0" {
    errors.append("catalog must contain exactly reviewed runtime 1.1.0")
}

if let entry = catalog.entries.first {
    let expectedPackage = PackageIdentity(
        runtimeVersion: package.runtimeVersion,
        assetName: package.assetName,
        sha256: package.sha256,
        installerTeamID: package.installerTeamID,
        signerCommonName: package.signerCommonName,
        receiptIdentifier: package.receiptIdentifier
    )
    if entry.package != expectedPackage {
        errors.append("catalog package identity differs from the reviewed manifest")
    }
    if entry.adapterPackageVersion != entry.runtimeVersion {
        errors.append("adapter package version differs from runtime version")
    }
    if entry.capabilityIDs != Set(contract.operations.map(\.id)) || entry.capabilityIDs.count != 61 {
        errors.append("capability IDs differ from the 61-operation contract")
    }
    let probes = [
        "health", "containers", "images", "builder", "networks", "volumes",
        "registries", "machines", "diskUsage", "configuration", "capabilities"
    ]
    if entry.requiredProbeIDs != probes {
        errors.append("baseline probe set or order differs from the reviewed eleven")
    }
    if entry.attestation.source != "embeddedPhysicalGate" || entry.attestation.id.isEmpty {
        errors.append("entry lacks embedded physical-test authority")
    }
}

guard errors.isEmpty else {
    fail(errors)
}

print("Compatibility catalog PASS: 1 reviewed runtime, 61 capabilities, 11 baseline probes")

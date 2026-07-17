#!/usr/bin/swift
import CryptoKit
import Foundation

private struct ResolvedState: Decodable {
    let revision: String
    let version: String?
}

private struct ResolvedPin: Decodable {
    let identity: String
    let location: String
    let state: ResolvedState
}

private struct Resolved: Decodable {
    let pins: [ResolvedPin]
}

private struct Inventory: Decodable {
    struct Dependency: Decodable {
        let identity: String
        let name: String
        let version: String
        let sourceURL: String
        let revision: String
        let licenseID: String
        let licenseFile: String
        let licenseSHA256: String
        let copyrightNotice: String
        let relationship: String
        let products: [String]
    }

    let schemaVersion: Int
    let dependencies: [Dependency]
}

private let allowedLicenses = ["Apache-2.0", "MIT", "BSD-3-Clause"]
private let forbiddenMarkers = ["GPL-", "AGPL-", "LGPL-", "unknown", "unreviewed"]

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func fail(_ errors: [String]) -> Never {
    for error in errors.sorted() {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
    }
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail(["usage: check-licenses.swift Package.resolved dependencies.json licenses-directory notices-file"])
}

let decoder = JSONDecoder()
guard let resolved = try? decoder.decode(
    Resolved.self,
    from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
) else { fail(["invalid Package.resolved"]) }
guard let inventory = try? decoder.decode(
    Inventory.self,
    from: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
) else { fail(["invalid dependency inventory"]) }
guard inventory.schemaVersion == 1 else { fail(["unsupported dependency inventory schema"]) }

let licenseRoot = URL(fileURLWithPath: arguments[3], isDirectory: true)
let notices = (try? String(contentsOfFile: arguments[4], encoding: .utf8)) ?? ""
var errors: [String] = []
private let inventoryByID = Dictionary(uniqueKeysWithValues: inventory.dependencies.map { ($0.identity, $0) })
private let resolvedByID = Dictionary(uniqueKeysWithValues: resolved.pins.map { ($0.identity, $0) })

if inventoryByID.count != inventory.dependencies.count {
    errors.append("dependency identities must be unique")
}

if Set(inventoryByID.keys) != Set(resolvedByID.keys) {
    errors.append("inventory must exactly match all resolved package identities")
}

for (identity, pin) in resolvedByID {
    guard let dependency = inventoryByID[identity] else { continue }
    if dependency.version != pin.state.version {
        errors.append("\(identity): version differs from Package.resolved")
    }
    if dependency.revision != pin.state.revision {
        errors.append("\(identity): revision differs from Package.resolved")
    }
    if dependency.sourceURL.lowercased() != pin.location.lowercased() {
        errors.append("\(identity): source URL differs from Package.resolved")
    }
    let hasAllowedLicense = allowedLicenses.contains(dependency.licenseID)
    let hasForbiddenMarker = forbiddenMarkers.contains(
        where: dependency.licenseID.localizedCaseInsensitiveContains
    )
    if hasAllowedLicense == false || hasForbiddenMarker {
        errors.append("\(identity): forbidden or unreviewed license \(dependency.licenseID)")
    }
    if dependency.name.isEmpty || dependency.copyrightNotice.isEmpty || dependency.products.isEmpty {
        errors.append("\(identity): name, copyright notice, and shipped products are required")
    }
    if dependency.relationship != "direct", dependency.relationship != "transitive" {
        errors.append("\(identity): relationship must be direct or transitive")
    }
    let licenseURL = licenseRoot.appending(path: dependency.licenseFile)
    guard let licenseData = try? Data(contentsOf: licenseURL), licenseData.isEmpty == false else {
        errors.append("\(identity): copied license is missing")
        continue
    }
    if sha256(licenseData) != dependency.licenseSHA256 {
        errors.append("\(identity): copied license hash differs")
    }
    guard let text = String(data: licenseData, encoding: .utf8) else {
        errors.append("\(identity): copied license is not UTF-8")
        continue
    }
    switch dependency.licenseID {
    case "Apache-2.0" where text.contains("Apache License") == false:
        errors.append("\(identity): copied text does not identify Apache-2.0")
    case "MIT" where text.contains("Permission is hereby granted") == false:
        errors.append("\(identity): copied text does not identify MIT")
    case "BSD-3-Clause" where text.contains("Neither the name") == false:
        errors.append("\(identity): copied text does not identify BSD-3-Clause")
    default:
        break
    }
    if dependency.relationship == "direct" {
        let requiredValues = [dependency.name, dependency.version, dependency.licenseID, dependency.sourceURL]
        for required in requiredValues where notices.contains(required) == false {
            errors.append("notices missing direct dependency value: \(required)")
        }
    }
}

if errors.isEmpty == false {
    fail(errors)
}

print("License policy PASS: \(inventory.dependencies.count) resolved packages, exact licenses and notices")

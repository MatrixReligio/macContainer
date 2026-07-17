#!/usr/bin/swift
import CryptoKit
import Foundation

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

    let dependencies: [Dependency]
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func gitCommit(repoRoot: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", repoRoot.path, "rev-parse", "HEAD"]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("unable to resolve source commit") }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let commit = String(data: data, encoding: .utf8) else { fail("source commit is not UTF-8") }
    return commit.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func purl(for dependency: Inventory.Dependency) -> String {
    guard let url = URL(string: dependency.sourceURL) else {
        return "pkg:generic/\(dependency.identity)@\(dependency.version)?commit=\(dependency.revision)"
    }
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        .replacingOccurrences(of: ".git", with: "")
    return "pkg:github/\(path)@\(dependency.version)?commit=\(dependency.revision)"
}

private func identifier(_ value: String) -> String {
    let allowed = value.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) || scalar == "-" ? Character(String(scalar)) : "-"
    }
    return String(allowed)
}

private func uuid(from value: String) -> String {
    let digest = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    let section1 = hex.prefix(8)
    let section2 = hex.dropFirst(8).prefix(4)
    let section3 = hex.dropFirst(13).prefix(3)
    let section4 = hex.dropFirst(17).prefix(3)
    let section5 = hex.dropFirst(20).prefix(12)
    return "\(section1)-\(section2)-4\(section3)-a\(section4)-\(section5)"
}

private func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try data.write(to: url, options: .atomic)
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let inventoryURL = repoRoot.appending(path: "Config/dependencies.json")
guard let inventory = try? JSONDecoder().decode(Inventory.self, from: Data(contentsOf: inventoryURL)) else {
    fail("invalid Config/dependencies.json")
}

guard let epochText = ProcessInfo.processInfo.environment["SOURCE_DATE_EPOCH"],
      let epoch = TimeInterval(epochText), epoch >= 0
else { fail("SOURCE_DATE_EPOCH is required") }

let timestampFormatter = ISO8601DateFormatter()
timestampFormatter.formatOptions = [.withInternetDateTime]
let timestamp = timestampFormatter.string(from: Date(timeIntervalSince1970: epoch))
let commit = try gitCommit(repoRoot: repoRoot)
let appVersion = "0.1.0"
let appBuild = "1"
let appRef = "pkg:generic/container.matrixreligio.com@\(appVersion)?build=\(appBuild)&commit=\(commit)"
private let dependencies = inventory.dependencies.sorted { purl(for: $0) < purl(for: $1) }

let components: [[String: Any]] = dependencies.map { dependency in
    [
        "bom-ref": purl(for: dependency),
        "type": "library",
        "name": dependency.name,
        "version": dependency.version,
        "purl": purl(for: dependency),
        "licenses": [["license": ["id": dependency.licenseID]]],
        "externalReferences": [["type": "vcs", "url": dependency.sourceURL]],
        "properties": [
            ["name": "maccontainer:revision", "value": dependency.revision],
            ["name": "maccontainer:relationship", "value": dependency.relationship],
            ["name": "maccontainer:products", "value": dependency.products.joined(separator: ",")],
            ["name": "maccontainer:license-file", "value": "ThirdPartyLicenses/\(dependency.licenseFile)"],
            ["name": "maccontainer:license-sha256", "value": dependency.licenseSHA256]
        ]
    ]
}

let cyclonedx: [String: Any] = [
    "bomFormat": "CycloneDX",
    "specVersion": "1.6",
    "serialNumber": "urn:uuid:\(uuid(from: appRef))",
    "version": 1,
    "metadata": [
        "timestamp": timestamp,
        "component": [
            "bom-ref": appRef,
            "type": "application",
            "name": "MacContainer",
            "version": appVersion,
            "purl": appRef,
            "supplier": ["name": "Matrix Religio"]
        ],
        "properties": [
            ["name": "maccontainer:build", "value": appBuild],
            ["name": "maccontainer:source-commit", "value": commit]
        ]
    ],
    "components": components,
    "dependencies": [["ref": appRef, "dependsOn": dependencies.map { purl(for: $0) }]]
]

var spdxPackages: [[String: Any]] = [[
    "SPDXID": "SPDXRef-Package-MacContainer",
    "name": "MacContainer",
    "versionInfo": appVersion,
    "downloadLocation": "https://github.com/matrixreligio/macContainer",
    "filesAnalyzed": false,
    "licenseConcluded": "Apache-2.0",
    "licenseDeclared": "Apache-2.0",
    "copyrightText": "Copyright 2026 Matrix Religio",
    "externalRefs": [[
        "referenceCategory": "PACKAGE-MANAGER",
        "referenceType": "purl",
        "referenceLocator": appRef
    ]]
]]
var spdxFiles: [[String: Any]] = []
var relationships: [[String: String]] = [[
    "spdxElementId": "SPDXRef-DOCUMENT",
    "relationshipType": "DESCRIBES",
    "relatedSpdxElement": "SPDXRef-Package-MacContainer"
]]

for dependency in dependencies {
    let packageID = "SPDXRef-Package-\(identifier(dependency.identity))"
    let fileID = "SPDXRef-LicenseFile-\(identifier(dependency.identity))"
    spdxPackages.append([
        "SPDXID": packageID,
        "name": dependency.name,
        "versionInfo": dependency.version,
        "downloadLocation": dependency.sourceURL,
        "filesAnalyzed": false,
        "licenseConcluded": dependency.licenseID,
        "licenseDeclared": dependency.licenseID,
        "copyrightText": dependency.copyrightNotice,
        "sourceInfo": "Revision \(dependency.revision); products: \(dependency.products.joined(separator: ", "))",
        "externalRefs": [[
            "referenceCategory": "PACKAGE-MANAGER",
            "referenceType": "purl",
            "referenceLocator": purl(for: dependency)
        ]]
    ])
    spdxFiles.append([
        "SPDXID": fileID,
        "fileName": "ThirdPartyLicenses/\(dependency.licenseFile)",
        "checksums": [["algorithm": "SHA256", "checksumValue": dependency.licenseSHA256]],
        "licenseConcluded": "NOASSERTION",
        "licenseInfoInFiles": [dependency.licenseID],
        "copyrightText": dependency.copyrightNotice
    ])
    relationships.append([
        "spdxElementId": "SPDXRef-Package-MacContainer",
        "relationshipType": "DEPENDS_ON",
        "relatedSpdxElement": packageID,
        "comment": dependency.relationship
    ])
    relationships.append([
        "spdxElementId": packageID,
        "relationshipType": "OTHER",
        "relatedSpdxElement": fileID,
        "comment": "Exact copied license text"
    ])
}

let spdx: [String: Any] = [
    "spdxVersion": "SPDX-2.3",
    "dataLicense": "CC0-1.0",
    "SPDXID": "SPDXRef-DOCUMENT",
    "name": "MacContainer-\(appVersion)-\(commit.prefix(12))",
    "documentNamespace": "https://container.matrixreligio.com/sbom/\(uuid(from: appRef))",
    "creationInfo": [
        "created": timestamp,
        "creators": ["Organization: Matrix Religio", "Tool: MacContainer SBOM generator"]
    ],
    "packages": spdxPackages,
    "files": spdxFiles,
    "relationships": relationships
]

let output = repoRoot.appending(path: "dist", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let cyclonedxURL = output.appending(path: "MacContainer.cdx.json")
let spdxURL = output.appending(path: "MacContainer.spdx.json")
try writeJSON(cyclonedx, to: cyclonedxURL)
try writeJSON(spdx, to: spdxURL)
let checksumText = try "\(sha256(Data(contentsOf: cyclonedxURL)))  dist/MacContainer.cdx.json\n" +
    "\(sha256(Data(contentsOf: spdxURL)))  dist/MacContainer.spdx.json\n"
try Data(checksumText.utf8).write(to: output.appending(path: "sbom-checksums.txt"), options: .atomic)
print("SBOM generation PASS: \(dependencies.count) packages, deterministic timestamp \(timestamp)")

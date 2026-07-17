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

private struct Dependency: Encodable {
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

private struct Inventory: Encodable {
    let schemaVersion: Int
    let dependencies: [Dependency]
}

private let direct = ["container", "containerization", "sparkle", "swift-toml", "swiftterm"]
private let displayNames = [
    "container": "Apple container",
    "containerization": "Apple containerization",
    "sparkle": "Sparkle",
    "swift-toml": "swift-toml",
    "swiftterm": "SwiftTerm"
]
private let directProducts = [
    "container": [
        "ContainerAPIClient", "ContainerBuild", "ContainerNetworkClient", "ContainerPersistence",
        "ContainerPlugin", "ContainerResource", "ContainerXPC", "MachineAPIClient", "TerminalProgress"
    ],
    "containerization": ["Containerization", "ContainerizationArchive"],
    "sparkle": ["Sparkle"],
    "swift-toml": ["TOML"],
    "swiftterm": ["SwiftTerm"]
]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func licenseID(for text: String) -> String? {
    if text.contains("Apache License"), text.contains("Version 2.0") {
        return "Apache-2.0"
    }
    if text.contains("Permission is hereby granted") {
        return "MIT"
    }
    if text.contains("Neither the name"), text.contains("Redistribution and use") {
        return "BSD-3-Clause"
    }
    return nil
}

private func copyrightNotice(checkout: URL, licenseData: Data, revision: String) -> String {
    let manager = FileManager.default
    let notices = ((try? manager.contentsOfDirectory(at: checkout, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.lastPathComponent.lowercased().hasPrefix("notice") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let licenseText = String(data: licenseData, encoding: .utf8) ?? ""
    let sources = notices.compactMap { try? String(contentsOf: $0, encoding: .utf8) } + [licenseText]
    var lines: [String] = []
    for text in sources {
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercase = trimmed.lowercased()
            let isBoilerplate = lowercase.hasPrefix("copyright notice") ||
                lowercase.hasPrefix("copyright license") || lowercase.hasPrefix("copyright owner")
            let isCopyright = lowercase.hasPrefix("copyright ") ||
                lowercase.hasPrefix("copyright (") || trimmed.hasPrefix("Copyright ©")
            if isBoilerplate == false, isCopyright {
                lines.append(trimmed)
            }
        }
    }
    lines.removeAll { $0.contains("[yyyy]") || $0.contains("<OWNER>") }
    if lines.isEmpty == false {
        return lines.prefix(3).joined(separator: " ")
    }
    return "See copied upstream license text from immutable revision \(revision)."
}

private func checkoutURL(identity: String, root: URL) -> URL? {
    let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return directories.first { $0.lastPathComponent.lowercased() == identity.lowercased() }
}

private func manifestProducts(checkout: URL, fallback: String) throws -> [String] {
    let source = try String(contentsOf: checkout.appending(path: "Package.swift"), encoding: .utf8)
    let pattern = #"\.(?:library|executable|plugin)\s*\(\s*name\s*:\s*"([^"]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [fallback] }
    let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
    let products = matches.compactMap { match -> String? in
        guard let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }
    let unique = Array(Set(products)).sorted()
    return unique.isEmpty ? [fallback] : unique
}

let arguments = CommandLine.arguments
guard arguments.count == 6 else {
    fail("usage: import-dependency-licenses.swift Package.resolved checkouts config licenses notices")
}

let resolvedURL = URL(fileURLWithPath: arguments[1])
let checkoutsURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
let configURL = URL(fileURLWithPath: arguments[3])
let licensesURL = URL(fileURLWithPath: arguments[4], isDirectory: true)
let noticesURL = URL(fileURLWithPath: arguments[5])
let decoder = JSONDecoder()
guard let resolved = try? decoder.decode(Resolved.self, from: Data(contentsOf: resolvedURL)) else {
    fail("invalid Package.resolved")
}

try FileManager.default.createDirectory(
    at: configURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try FileManager.default.createDirectory(at: licensesURL, withIntermediateDirectories: true)

private var dependencies: [Dependency] = []
for pin in resolved.pins.sorted(by: { $0.identity < $1.identity }) {
    guard let version = pin.state.version else { fail("unversioned dependency: \(pin.identity)") }
    guard let checkout = checkoutURL(identity: pin.identity, root: checkoutsURL) else {
        fail("missing checkout: \(pin.identity)")
    }
    let candidates = ["LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING"]
    guard let sourceLicense = candidates.map({ checkout.appending(path: $0) }).first(where: {
        FileManager.default.fileExists(atPath: $0.path)
    }) else { fail("missing upstream license: \(pin.identity)") }
    let licenseData = try Data(contentsOf: sourceLicense)
    guard let text = String(data: licenseData, encoding: .utf8) else {
        fail("license is not UTF-8: \(pin.identity)")
    }
    guard let license = licenseID(for: text) else { fail("unreviewed license: \(pin.identity)") }
    let destinationName = "\(pin.identity).txt"
    try licenseData.write(to: licensesURL.appending(path: destinationName), options: .atomic)

    let products: [String] = if let reviewedProducts = directProducts[pin.identity] {
        reviewedProducts
    } else {
        try manifestProducts(checkout: checkout, fallback: pin.identity)
    }
    dependencies.append(Dependency(
        identity: pin.identity,
        name: displayNames[pin.identity] ?? pin.identity,
        version: version,
        sourceURL: pin.location,
        revision: pin.state.revision,
        licenseID: license,
        licenseFile: destinationName,
        licenseSHA256: sha256(licenseData),
        copyrightNotice: copyrightNotice(checkout: checkout, licenseData: licenseData, revision: pin.state.revision),
        relationship: direct.contains(pin.identity) ? "direct" : "transitive",
        products: products
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(Inventory(schemaVersion: 1, dependencies: dependencies)).write(to: configURL, options: .atomic)

var notice = """
MacContainer third-party notices
================================

This file is generated from Package.resolved and exact license texts copied from immutable revisions.
Package names and versions do not imply endorsement of MacContainer.

"""
for dependency in dependencies.sorted(by: { lhs, rhs in
    if lhs.relationship != rhs.relationship {
        return lhs.relationship == "direct"
    }
    return lhs.identity < rhs.identity
}) {
    notice += """
    \(dependency.name) \(dependency.version) [\(dependency.relationship)]
    \(dependency.copyrightNotice)
    License: \(dependency.licenseID)
    Source: \(dependency.sourceURL)
    Revision: \(dependency.revision)
    Products: \(dependency.products.joined(separator: ", "))
    Copied license: ThirdPartyLicenses/\(dependency.licenseFile) (SHA-256 \(dependency.licenseSHA256))

    """
}

try Data(notice.utf8).write(to: noticesURL, options: .atomic)
print("Imported exact licenses for \(dependencies.count) resolved packages")

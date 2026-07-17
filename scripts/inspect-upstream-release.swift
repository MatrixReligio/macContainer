#!/usr/bin/swift
import CryptoKit
import Foundation

private struct Release: Decodable {
    let tagName: String
    let htmlURL: URL
    let publishedAt: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct Asset: Decodable {
    let name: String
    let size: Int
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

private enum InspectorError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidRelease
    case missingInstaller
    case sizeMismatch

    var description: String {
        switch self {
        case .invalidArguments: "expected --fixture release.json [--asset-file installer.pkg]"
        case .invalidRelease: "release metadata failed strict validation"
        case .missingInstaller: "signed installer asset is absent"
        case .sizeMismatch: "downloaded installer size differs from release metadata"
        }
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let fixtureIndex = arguments.firstIndex(of: "--fixture"),
          arguments.indices.contains(fixtureIndex + 1)
    else {
        throw InspectorError.invalidArguments
    }
    let releaseURL = URL(fileURLWithPath: arguments[fixtureIndex + 1]).standardizedFileURL
    let release = try JSONDecoder().decode(Release.self, from: Data(contentsOf: releaseURL))
    let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    guard version.split(separator: ".").count == 3,
          version.split(separator: ".").allSatisfy({ $0.allSatisfy(\.isNumber) }),
          release.htmlURL.scheme == "https"
    else {
        throw InspectorError.invalidRelease
    }
    guard let asset = release.assets.first(where: {
        $0.name.hasSuffix("installer-signed.pkg") && $0.browserDownloadURL.scheme == "https"
    }) else {
        throw InspectorError.missingInstaller
    }

    var independentDigest = "NOT CALCULATED (metadata-only inspection)"
    if let assetIndex = arguments.firstIndex(of: "--asset-file"), arguments.indices.contains(assetIndex + 1) {
        let assetURL = URL(fileURLWithPath: arguments[assetIndex + 1]).standardizedFileURL
        let handle = try FileHandle(forReadingFrom: assetURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            byteCount += chunk.count
            hasher.update(data: chunk)
        }
        guard byteCount == asset.size else { throw InspectorError.sizeMismatch }
        independentDigest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    print("Compatibility candidate: Apple container \(version)")
    print("")
    print("Status: UNVERIFIED")
    print("")
    print("- Upstream tag: \(release.tagName)")
    print("- Published: \(release.publishedAt)")
    print("- Release: \(release.htmlURL.absoluteString)")
    print("- Asset: \(asset.name)")
    print("- Asset size: \(asset.size) bytes")
    print("- Upstream digest: \(asset.digest ?? "NOT PROVIDED")")
    print("- Independent SHA-256: \(independentDigest)")
    print("")
    print("This issue is intake metadata only. It cannot grant compatibility or authorize installation.")
    print("A signed physical-test attestation and reviewed app catalog change are required in a separate PR.")
} catch {
    FileHandle.standardError.write(Data("Upstream release inspection FAIL: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}

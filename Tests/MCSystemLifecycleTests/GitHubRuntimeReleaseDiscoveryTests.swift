import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("GitHub runtime release discovery")
struct GitHubRuntimeReleaseDiscoveryTests {
    @Test func `accepts only exact release asset URL and mandatory digest`() async throws {
        let endpoint = GitHubRuntimeReleaseDiscovery.defaultEndpoint
        let body = Data("""
        {
          "tag_name":"1.1.0",
          "assets":[{
            "name":"container-1.1.0-installer-signed.pkg",
            "browser_download_url":"https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg",
            "digest":"sha256:0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714"
          }]
        }
        """.utf8)
        let discovery = GitHubRuntimeReleaseDiscovery(loader: FixedDiscoveryLoader(response: .init(
            statusCode: 200,
            finalURL: endpoint,
            body: body,
            headers: ["etag": "reviewed-etag"]
        )))

        let result = try await discovery.discover(validators: nil)

        guard case let .available(candidate, validators) = result else {
            Issue.record("Expected an exact release candidate")
            return
        }
        #expect(candidate.version == "1.1.0")
        #expect(candidate.packageSHA256 == "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714")
        #expect(validators.etag == "reviewed-etag")
    }

    @Test(arguments: [
        "https://github.com/attacker/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg",
        "https://github.com/apple/container/releases/download/1.1.0/renamed-installer-signed.pkg",
        "https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg?swap=1"
    ])
    func `rejects substituted package URLs`(_ packageURL: String) async throws {
        let body = Data("""
        {"tag_name":"1.1.0","assets":[{
          "name":"container-1.1.0-installer-signed.pkg",
          "browser_download_url":"\(packageURL)",
          "digest":"sha256:\(String(repeating: "a", count: 64))"
        }]}
        """.utf8)
        let discovery = GitHubRuntimeReleaseDiscovery(loader: FixedDiscoveryLoader(response: .init(
            statusCode: 200,
            finalURL: GitHubRuntimeReleaseDiscovery.defaultEndpoint,
            body: body,
            headers: [:]
        )))

        #expect(try await discovery.discover(validators: nil) == .offline)
    }

    @Test func `rejects redirected API response and missing digest`() async throws {
        let body = Data("""
        {
          "tag_name":"1.1.0",
          "assets":[{
            "name":"container-1.1.0-installer-signed.pkg",
            "browser_download_url":"https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg"
          }]
        }
        """.utf8)
        let redirected = GitHubRuntimeReleaseDiscovery(loader: FixedDiscoveryLoader(response: .init(
            statusCode: 200,
            finalURL: URL(string: "https://example.com/redirect")!,
            body: body,
            headers: [:]
        )))
        let missingDigest = GitHubRuntimeReleaseDiscovery(loader: FixedDiscoveryLoader(response: .init(
            statusCode: 200,
            finalURL: GitHubRuntimeReleaseDiscovery.defaultEndpoint,
            body: body,
            headers: [:]
        )))

        #expect(try await redirected.discover(validators: nil) == .offline)
        #expect(try await missingDigest.discover(validators: nil) == .offline)
    }
}

private struct FixedDiscoveryLoader: RuntimeReleaseDiscoveryDataLoading {
    let response: RuntimeReleaseDiscoveryHTTPResponse

    func load(
        endpoint _: URL,
        validators _: HTTPValidators?
    ) async throws -> RuntimeReleaseDiscoveryHTTPResponse {
        response
    }
}

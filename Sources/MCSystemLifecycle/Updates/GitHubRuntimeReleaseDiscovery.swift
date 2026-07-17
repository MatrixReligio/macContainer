import Foundation

public struct RuntimeReleaseDiscoveryHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let finalURL: URL
    public let body: Data
    public let headers: [String: String]

    public init(statusCode: Int, finalURL: URL, body: Data, headers: [String: String]) {
        self.statusCode = statusCode
        self.finalURL = finalURL
        self.body = body
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
    }
}

public protocol RuntimeReleaseDiscoveryDataLoading: Sendable {
    func load(
        endpoint: URL,
        validators: HTTPValidators?
    ) async throws -> RuntimeReleaseDiscoveryHTTPResponse
}

public struct URLSessionRuntimeReleaseDiscoveryLoader: RuntimeReleaseDiscoveryDataLoading, Sendable {
    public init() {}

    public func load(
        endpoint: URL,
        validators: HTTPValidators?
    ) async throws -> RuntimeReleaseDiscoveryHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let session = URLSession(
            configuration: configuration,
            delegate: RuntimeDiscoveryRedirectRefuser(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacContainer/0.1 contact@matrixreligio.com", forHTTPHeaderField: "User-Agent")
        request.setValue(validators?.etag, forHTTPHeaderField: "If-None-Match")
        request.setValue(validators?.lastModified, forHTTPHeaderField: "If-Modified-Since")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw RuntimeReleaseDiscoveryError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            guard let key = field.key as? String, let value = field.value as? String else { return }
            result[key.lowercased()] = value
        }
        return .init(
            statusCode: response.statusCode,
            finalURL: finalURL,
            body: data,
            headers: headers
        )
    }
}

private final class RuntimeDiscoveryRedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct GitHubRuntimeReleaseDiscovery: RuntimeReleaseDiscovering, Sendable {
    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    public static let defaultEndpoint = URL(
        string: "https://api.github.com/repos/apple/container/releases/latest"
    )!

    private let endpoint: URL
    private let loader: any RuntimeReleaseDiscoveryDataLoading

    public init(
        endpoint: URL = GitHubRuntimeReleaseDiscovery.defaultEndpoint,
        loader: any RuntimeReleaseDiscoveryDataLoading = URLSessionRuntimeReleaseDiscoveryLoader()
    ) {
        self.endpoint = endpoint
        self.loader = loader
    }

    public func discover(validators: HTTPValidators?) async throws -> RuntimeReleaseDiscoveryResult {
        guard Self.isExactEndpoint(endpoint) else { return .offline }
        do {
            let response = try await loader.load(endpoint: endpoint, validators: validators)
            try Task.checkCancellation()
            guard response.finalURL == endpoint, response.body.count <= 2_000_000 else {
                return .offline
            }
            if response.statusCode == 304 { return .notModified }
            if response.statusCode == 403 || response.statusCode == 429 {
                let reset = response.headers["x-ratelimit-reset"]
                    .flatMap(TimeInterval.init)
                    .map(Date.init(timeIntervalSince1970:)) ?? Date().addingTimeInterval(3600)
                return .rateLimited(reset: reset)
            }
            guard response.statusCode == 200 else { return .offline }
            let release = try JSONDecoder().decode(Release.self, from: response.body)
            guard release.assets.count <= 256,
                  let version = Self.strictVersion(release.tagName)
            else {
                return .offline
            }
            let expectedName = "container-\(version)-installer-signed.pkg"
            let matches = release.assets.filter { $0.name == expectedName }
            guard matches.count == 1,
                  let asset = matches.first,
                  let packageURL = URL(string: asset.browserDownloadURL),
                  Self.isExactPackageURL(packageURL, version: version, assetName: expectedName),
                  let digest = asset.digest,
                  digest.hasPrefix("sha256:")
            else {
                return .offline
            }
            let sha256 = String(digest.dropFirst("sha256:".count))
            guard Self.isSHA256(sha256) else { return .offline }
            return .available(
                .init(version: version, packageURL: packageURL, packageSHA256: sha256),
                validators: .init(
                    etag: Self.safeHeader(response.headers["etag"], maximumBytes: 512),
                    lastModified: Self.safeHeader(response.headers["last-modified"], maximumBytes: 128)
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .offline
        }
    }

    private static func isExactEndpoint(_ url: URL) -> Bool {
        url == defaultEndpoint && url.user == nil && url.password == nil &&
            url.query == nil && url.fragment == nil
    }

    private static func strictVersion(_ value: String) -> String? {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }
        return version
    }

    private static func isExactPackageURL(_ url: URL, version: String, assetName: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" &&
            url.user == nil && url.password == nil && url.port == nil &&
            url.query == nil && url.fragment == nil &&
            url.path == "/apple/container/releases/download/\(version)/\(assetName)"
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isNumber || ("a" ... "f").contains($0) }
    }

    private static func safeHeader(_ value: String?, maximumBytes: Int) -> String? {
        guard let value,
              !value.isEmpty,
              value.utf8.count <= maximumBytes,
              !value.contains("\n"),
              !value.contains("\r")
        else {
            return nil
        }
        return value
    }
}

public enum RuntimeReleaseDiscoveryError: Error, Equatable, Sendable {
    case invalidResponse
}

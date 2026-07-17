import AppKit
import Foundation
import MCCompatibility
import MCSystemLifecycle
import UserNotifications

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

struct GitHubRuntimeReleaseDiscovery: RuntimeReleaseDiscovering {
    let endpoint: URL
    let session: URLSession

    init(
        endpoint: URL = UpdateAgentConfiguration.githubReleaseAPI,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func discover(validators: HTTPValidators?) async throws -> RuntimeReleaseDiscoveryResult {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacContainer/0.1 contact@matrixreligio.com", forHTTPHeaderField: "User-Agent")
        request.setValue(validators?.etag, forHTTPHeaderField: "If-None-Match")
        request.setValue(validators?.lastModified, forHTTPHeaderField: "If-Modified-Since")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .offline }
            if response.statusCode == 304 {
                return .notModified
            }
            if response.statusCode == 403 || response.statusCode == 429 {
                let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap(TimeInterval.init)
                    .map(Date.init(timeIntervalSince1970:)) ?? Date().addingTimeInterval(3600)
                return .rateLimited(reset: reset)
            }
            guard response.statusCode == 200 else { return .offline }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let asset = release.assets.first(where: {
                $0.name.hasSuffix("installer-signed.pkg") && $0.browserDownloadURL.scheme == "https"
            }) else {
                return .notModified
            }
            let digest = asset.digest?.replacingOccurrences(of: "sha256:", with: "") ?? ""
            let candidate = RuntimeReleaseCandidate(
                version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v")),
                packageURL: asset.browserDownloadURL,
                packageSHA256: digest
            )
            return .available(
                candidate,
                validators: HTTPValidators(
                    etag: response.value(forHTTPHeaderField: "ETag"),
                    lastModified: response.value(forHTTPHeaderField: "Last-Modified")
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .offline
        }
    }
}

struct EmbeddedCatalogHandoffCoordinator: RuntimeUpdateCoordinating {
    func process(_ candidate: RuntimeReleaseCandidate) async -> RuntimeUpdateState {
        guard let catalog = try? CompatibilityCatalog.bundled(),
              let entry = catalog.entry(runtimeVersion: candidate.version)
        else {
            return .held(.unknownRuntime)
        }
        guard candidate.packageURL.scheme == "https",
              candidate.packageSHA256 == entry.package.sha256
        else {
            return .held(.packageIdentityMismatch)
        }
        return .available(version: candidate.version)
    }
}

final class UpdateAgentPresenter: UpdateAgentPresenting, @unchecked Sendable {
    func isAppRunning() async -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "container.matrixreligio.com" }
    }

    func publish(_ state: RuntimeUpdateState) async {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let connection = NSXPCConnection(machServiceName: UpdateAgentXPCIdentity.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: UpdateAgentStatusXPC.self)
        connection.resume()
        await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                connection.invalidate()
                continuation.resume()
            } as? UpdateAgentStatusXPC
            guard let proxy else {
                connection.invalidate()
                continuation.resume()
                return
            }
            proxy.publishStatus(data) { _ in
                connection.invalidate()
                continuation.resume()
            }
        }
    }

    func notify(_ state: RuntimeUpdateState) async {
        let content = UNMutableNotificationContent()
        content.title = "MacContainer runtime update"
        content.body = notificationBody(for: state)
        let request = UNNotificationRequest(identifier: "runtime-update", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func notificationBody(for state: RuntimeUpdateState) -> String {
        switch state {
        case let .available(version): "Apple container \(version) is compatibility-approved and ready to review."
        case let .pending(reason): "The approved update is pending: \(reason.rawValue)."
        case let .held(reason): "The discovered runtime is held: \(reason.rawValue)."
        case .rolledBack: "The runtime update was rolled back. Open MacContainer for recovery details."
        case .recoveryRequired: "Runtime recovery requires attention in MacContainer."
        default: "Open MacContainer to review runtime update status."
        }
    }
}

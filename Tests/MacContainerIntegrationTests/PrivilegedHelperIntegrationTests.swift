import Foundation
import MCSystemLifecycle
import XCTest

final class PrivilegedHelperIntegrationTests: XCTestCase {
    func testEveryRequestDispatchesExactlyOneAllowlistedAdapterCallOverXPC() async throws {
        let adapter = RecordingPrivilegedSystemAdapter()
        let fixture = FixtureHelperConnection(adapter: adapter)
        defer { fixture.close() }
        let package = try TemporaryPackageFile()
        defer { package.cleanup() }
        let requests: [(PrivilegedRequest, FileHandle?)] = [
            (
                .installVerifiedPackage(.init(
                    runtimeVersion: "1.1.0",
                    sha256: String(repeating: "a", count: 64)
                )),
                package.handle
            ),
            (.removePayload(.init(
                manifestID: "apple-container-1.1.0",
                manifestSHA256: String(repeating: "b", count: 64)
            )), nil),
            (.forgetReceipt(identifier: "com.apple.container-installer"), nil),
            (.writeResolver(.init(name: "default", nameservers: ["192.168.64.1"])), nil),
            (.removeResolver(name: "default"), nil),
            (.createDNSDomain(.init(name: "dev.example", redirectIPv4: "192.0.2.10")), nil),
            (.deleteDNSDomain(name: "dev.example"), nil),
            (.applyPacketFilter(.init(anchor: "com.apple.container", subnetCIDR: "192.168.64.0/24")), nil),
            (.removePacketFilter(anchor: "com.apple.container"), nil),
            (.auditPacketFilter(anchor: "com.apple.container"), nil),
            (.removeKnownEmptyDirectories(manifestID: "apple-container-1.1.0"), nil)
        ]

        for (request, handle) in requests {
            let response = try await fixture.perform(data: PrivilegedRequestCodec.encode(request), package: handle)
            if request == .auditPacketFilter(anchor: "com.apple.container") {
                XCTAssertEqual(response.residuePresent, true)
            }
        }

        XCTAssertEqual(adapter.actions, [
            "install", "removePayload", "forgetReceipt", "writeResolver",
            "removeResolver", "createDNSDomain", "deleteDNSDomain",
            "applyPacketFilter", "removePacketFilter", "auditPacketFilter",
            "removeKnownEmptyDirectories"
        ])
    }

    func testOversizedUnknownAndSmuggledFileRequestsAreRejectedWithoutAdapterCall() async throws {
        let adapter = RecordingPrivilegedSystemAdapter()
        let fixture = FixtureHelperConnection(adapter: adapter)
        defer { fixture.close() }
        let package = try TemporaryPackageFile()
        defer { package.cleanup() }

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.perform(
                data: Data(repeating: 0x41, count: PrivilegedRequestCodec.maximumMessageBytes + 1),
                package: nil
            )
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.perform(data: Data(#"{"version":999}"#.utf8), package: nil)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.perform(
                data: PrivilegedRequestCodec.encode(.removeResolver(name: "default")),
                package: package.handle
            )
        }
        XCTAssertTrue(adapter.actions.isEmpty)
    }

    func testHelperConfigurationHasNoNetworkOrSandboxEntitlement() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlements = try String(
            contentsOf: root.appendingPathComponent("App/PrivilegedHelper/PrivilegedHelper.entitlements"),
            encoding: .utf8
        )
        let launchd = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: root.appendingPathComponent(
                "App/PrivilegedHelper/container.matrixreligio.com.helper.plist"
            )),
            format: nil
        ) as? [String: Any]

        XCTAssertFalse(entitlements.contains("com.apple.security.network"))
        XCTAssertFalse(entitlements.contains("com.apple.security.app-sandbox"))
        XCTAssertEqual(launchd?["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(launchd?["KeepAlive"] as? Bool, false)
        XCTAssertEqual(launchd?["ProcessType"] as? String, "Interactive")
    }
}

private final class FixtureHelperConnection: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener
    private let service: PrivilegedHelperService
    private let connection: NSXPCConnection

    init(adapter: RecordingPrivilegedSystemAdapter) {
        listener = .anonymous()
        service = PrivilegedHelperService(system: adapter)
        connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        super.init()
        listener.delegate = self
        listener.activate()
        connection.remoteObjectInterface = PrivilegedHelperXPC.interface()
        connection.activate()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = PrivilegedHelperXPC.interface()
        newConnection.exportedObject = service
        newConnection.activate()
        return true
    }

    func perform(data: Data, package: FileHandle?) async throws -> PrivilegedResponse {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? MCPrivilegedHelperXPCProtocol else {
                continuation.resume(throwing: FixtureError.proxy)
                return
            }
            proxy.perform(data, packageFile: package) { response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    do {
                        try continuation.resume(returning: PrivilegedResponseCodec.decode(response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: FixtureError.emptyResponse)
                }
            }
        }
    }

    func close() {
        connection.invalidate()
        listener.invalidate()
    }
}

private final class RecordingPrivilegedSystemAdapter: PrivilegedSystemAdapting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var actions: [String] {
        lock.withLock { storage }
    }

    func installVerifiedPackage(_: FileHandle, token _: PackageInstallToken) throws {
        record("install")
    }

    func removePayload(_: RemovePayloadRequest) throws {
        record("removePayload")
    }

    func forgetReceipt(identifier _: String) throws {
        record("forgetReceipt")
    }

    func writeResolver(_: ResolverRequest) throws {
        record("writeResolver")
    }

    func removeResolver(name _: String) throws {
        record("removeResolver")
    }

    func createDNSDomain(_: DNSDomainRequest) throws {
        record("createDNSDomain")
    }

    func deleteDNSDomain(name _: String) throws {
        record("deleteDNSDomain")
    }

    func applyPacketFilter(_: PacketFilterRequest) throws {
        record("applyPacketFilter")
    }

    func removePacketFilter(anchor _: String) throws {
        record("removePacketFilter")
    }

    func packetFilterRulesPresent(anchor _: String) throws -> Bool {
        record("auditPacketFilter")
        return true
    }

    func removeKnownEmptyDirectories(manifestID _: String) throws {
        record("removeKnownEmptyDirectories")
    }

    private func record(_ action: String) {
        lock.withLock { storage.append(action) }
    }
}

private final class TemporaryPackageFile {
    let url: URL
    let handle: FileHandle

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerHelperIntegration-\(UUID().uuidString).pkg")
        try Data("fixture".utf8).write(to: url)
        handle = try FileHandle(forReadingFrom: url)
    }

    func cleanup() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }
}

private enum FixtureError: Error {
    case emptyResponse
    case proxy
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}

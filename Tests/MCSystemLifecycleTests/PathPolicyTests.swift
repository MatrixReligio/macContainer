import Darwin
import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Privileged helper path and request policy")
struct PathPolicyTests {
    @Test(arguments: [
        "../../etc/passwd",
        "/usr/local/bin/../etc/passwd",
        "/tmp/link",
        "/usr/local/bin/shared-unowned",
        "/usr/local/bin",
        "/usr/local/libexec"
    ])
    func `rejects untrusted removal path`(_ path: String) {
        #expect(!PathPolicy.runtime110.allowsRemoval(path))
    }

    @Test func `allows exact manifest intersection only`() {
        let policy = PathPolicy.runtime110

        #expect(policy.allowsRemoval("/usr/local/bin/container"))
        #expect(policy.allowsRemoval("/usr/local/libexec/container/plugins/machine-apiserver/config.toml"))
        #expect(!policy.allowsRemoval("/usr/local/bin/container/extra"))
    }

    @Test(arguments: [
        "", ".", "../escape", "UPPER", "name/part", "name part", String(repeating: "a", count: 64)
    ])
    func `rejects unsafe resolver names`(_ name: String) {
        #expect(!PathPolicy.runtime110.allowsResolverName(name))
    }

    @Test func `allows normalized multi-label resolver names created by the runtime`() {
        #expect(PathPolicy.runtime110.allowsResolverName("web.test"))
        #expect(PathPolicy.runtime110.allowsResolverName("api-1.dev.test"))
        #expect(!PathPolicy.runtime110.allowsResolverName("-web.test"))
        #expect(!PathPolicy.runtime110.allowsResolverName("web-.test"))
        #expect(!PathPolicy.runtime110.allowsResolverName("containerization.web"))
    }

    @Test func `allows only exact packet filter anchor`() {
        #expect(PathPolicy.runtime110.allowsPacketFilterAnchor("com.apple.container"))
        #expect(!PathPolicy.runtime110.allowsPacketFilterAnchor("com.apple.container; flush all"))
        #expect(!PathPolicy.runtime110.allowsPacketFilterAnchor("com.apple.container.other"))
    }

    @Test func `rejects symlink hard link and time of check replacement`() throws {
        let fixture = try RemovalFixture()
        defer { fixture.cleanup() }
        let policy = PathPolicy(
            payload: [
                PayloadEntry(relativePath: "payload", kind: .file, sha256: String(repeating: "a", count: 64)),
                PayloadEntry(relativePath: "payload-symlink", kind: .file, sha256: String(repeating: "a", count: 64))
            ],
            installRoot: fixture.root.path,
            requiredOwner: geteuid()
        )

        #expect(throws: PathPolicyError.kindMismatch) {
            _ = try policy.authorizeRemoval(fixture.symlink.path)
        }
        #expect(throws: PathPolicyError.hardLink) {
            _ = try policy.authorizeRemoval(fixture.file.path)
        }

        try FileManager.default.removeItem(at: fixture.hardLink)
        let authorization = try policy.authorizeRemoval(fixture.file.path)
        try FileManager.default.removeItem(at: fixture.file)
        try Data("replacement".utf8).write(to: fixture.file)
        #expect(throws: PathPolicyError.changedAfterAuthorization) {
            try authorization.revalidate()
        }
    }

    @Test func `all twelve requests round trip through versioned bounded codec`() throws {
        let requests: [PrivilegedRequest] = [
            .installVerifiedPackage(.init(runtimeVersion: "1.1.0", sha256: String(repeating: "a", count: 64))),
            .removePayload(.init(
                manifestID: "apple-container-1.1.0",
                manifestSHA256: String(repeating: "b", count: 64)
            )),
            .forgetReceipt(identifier: "com.apple.container-installer"),
            .writeResolver(.init(name: "default", nameservers: ["192.168.64.1"])),
            .removeResolver(name: "default"),
            .removeEmptyResolverDirectory,
            .createDNSDomain(.init(name: "dev.example", redirectIPv4: "192.0.2.10")),
            .deleteDNSDomain(name: "dev.example"),
            .applyPacketFilter(.init(anchor: "com.apple.container", subnetCIDR: "192.168.64.0/24")),
            .removePacketFilter(anchor: "com.apple.container"),
            .auditPacketFilter(anchor: "com.apple.container"),
            .removeKnownEmptyDirectories(manifestID: "apple-container-1.1.0")
        ]

        for request in requests {
            let encoded = try PrivilegedRequestCodec.encode(request)
            #expect(try PrivilegedRequestCodec.decode(encoded) == request)
            #expect(encoded.count <= PrivilegedRequestCodec.maximumMessageBytes)
        }
    }

    @Test func `rejects oversized unknown and injection shaped requests`() throws {
        let oversized = Data(repeating: 0x41, count: PrivilegedRequestCodec.maximumMessageBytes + 1)
        #expect(throws: PrivilegedRequestError.messageTooLarge) {
            _ = try PrivilegedRequestCodec.decode(oversized)
        }
        #expect(throws: PrivilegedRequestError.invalidEncoding) {
            _ = try PrivilegedRequestCodec.decode(Data(#"{"version":999,"request":{}}"#.utf8))
        }
        #expect(throws: PrivilegedRequestError.invalidResolver) {
            try PrivilegedRequest.writeResolver(.init(name: "x; rm -rf /", nameservers: ["1.1.1.1"]))
                .validate(policy: .runtime110)
        }
        #expect(throws: PrivilegedRequestError.invalidResolver) {
            try PrivilegedRequest.createDNSDomain(.init(name: "dev.example", redirectIPv4: "127.0.0.1; pass all"))
                .validate(policy: .runtime110)
        }
    }
}

private final class RemovalFixture: @unchecked Sendable {
    let root: URL
    let file: URL
    let hardLink: URL
    let symlink: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerPathPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent("payload")
        hardLink = root.appendingPathComponent("payload-hardlink")
        symlink = root.appendingPathComponent("payload-symlink")
        try Data("fixture".utf8).write(to: file)
        try FileManager.default.linkItem(at: file, to: hardLink)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

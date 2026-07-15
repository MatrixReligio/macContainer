import CryptoKit
import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Kernel adapter")
struct KernelAdapterTests {
    @Test func `local binary is canonical readable and installed directly`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appending(path: "vmlinux")
        try Data("kernel".utf8).write(to: binary)
        let backend = FakeKernelBackend()
        let adapter = KernelAdapter(backend: backend, downloader: ForbiddenKernelDownloader(), temporaryRoot: root)

        let result = try await adapter.setLocalBinary(binary, platform: "linux/arm64", force: true)

        #expect(result.identifier == binary.path)
        #expect(await backend.binaryInstalls == [.init(url: binary, platform: "linux/arm64", force: true)])
    }

    @Test func `local archive is validated with the pinned member before direct install`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appending(path: "kernel.tar.zst")
        try Data("archive".utf8).write(to: archive)
        let backend = FakeKernelBackend()
        let validator = RecordingKernelArchiveValidator()
        let adapter = KernelAdapter(
            backend: backend,
            downloader: ForbiddenKernelDownloader(),
            archiveValidator: validator,
            temporaryRoot: root
        )

        _ = try await adapter.setLocalArchive(archive, platform: "arm64", force: false)

        let binaryPath = "opt/kata/share/kata-containers/vmlinux-6.18.15-186"
        #expect(await validator.validatedPaths == [binaryPath])
        #expect(await backend.archiveInstalls == [
            .init(url: archive, binaryPath: binaryPath, platform: "linux/arm64", force: false)
        ])
    }

    @Test func `recommended release uses its pinned digest and allowlist`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("recommended".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let descriptor = try KernelArchiveDescriptor(
            url: #require(URL(string: "https://downloads.example.test/recommended.tar.zst")),
            binaryPath: "opt/kernel",
            expectedSHA256: digest,
            allowedHosts: ["downloads.example.test"]
        )
        let backend = FakeKernelBackend(recommendedDescriptor: descriptor)
        let downloader = RecordingKernelDownloader(data: payload)
        let validator = RecordingKernelArchiveValidator()
        let adapter = KernelAdapter(
            backend: backend,
            downloader: downloader,
            archiveValidator: validator,
            temporaryRoot: root
        )

        _ = try await adapter.setRecommended(platform: "amd64", force: true)

        #expect(await downloader.downloadCount == 1)
        #expect(await validator.validatedPaths == ["opt/kernel"])
        #expect(await backend.archiveInstalls.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func `remote archive without digest or exact host allowlist fails before network`() async throws {
        let backend = FakeKernelBackend()
        let downloader = RecordingKernelDownloader(data: Data())
        let adapter = KernelAdapter(backend: backend, downloader: downloader)
        let url = try #require(URL(string: "https://downloads.example.test/kernel.tar.zst"))

        await #expect(throws: KernelAdapterError.invalidDigest) {
            try await adapter.setVerifiedRemoteArchive(.init(
                url: url,
                expectedSHA256: "",
                allowedHosts: ["downloads.example.test"],
                platform: "arm64"
            ))
        }
        await #expect(throws: KernelAdapterError.hostNotAllowed("downloads.example.test")) {
            try await adapter.setVerifiedRemoteArchive(.init(
                url: url,
                expectedSHA256: String(repeating: "a", count: 64),
                allowedHosts: ["example.test"],
                platform: "arm64"
            ))
        }
        #expect(await downloader.downloadCount == 0)
        #expect(await backend.recommendedCount == 0)
    }

    @Test func `verified download checks digest validates archive and always cleans temporary files`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data("verified archive".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let backend = FakeKernelBackend()
        let downloader = RecordingKernelDownloader(data: payload)
        let validator = RecordingKernelArchiveValidator()
        let adapter = KernelAdapter(
            backend: backend,
            downloader: downloader,
            archiveValidator: validator,
            temporaryRoot: root
        )

        let result = try await adapter.setVerifiedRemoteArchive(.init(
            url: #require(URL(string: "https://downloads.example.test/kernel.tar.zst")),
            expectedSHA256: digest,
            allowedHosts: ["downloads.example.test"],
            platform: "amd64",
            force: true
        ))

        #expect(result.platform == "linux/amd64")
        #expect(await downloader.downloadCount == 1)
        #expect(await validator.validatedPaths == ["opt/kata/share/kata-containers/vmlinux-6.18.15-186"])
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func `digest mismatch never reaches archive or backend and cleans download`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = FakeKernelBackend()
        let downloader = RecordingKernelDownloader(data: Data("wrong".utf8))
        let validator = RecordingKernelArchiveValidator()
        let adapter = KernelAdapter(
            backend: backend,
            downloader: downloader,
            archiveValidator: validator,
            temporaryRoot: root
        )

        await #expect(throws: KernelAdapterError.digestMismatch) {
            try await adapter.setVerifiedRemoteArchive(.init(
                url: #require(URL(string: "https://downloads.example.test/kernel.tar.zst")),
                expectedSHA256: String(repeating: "0", count: 64),
                allowedHosts: ["downloads.example.test"],
                platform: "arm64"
            ))
        }

        #expect(await validator.validatedPaths.isEmpty)
        #expect(await backend.archiveInstalls.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func `production archive validator rejects traversal and escaping symlink`() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let traversal = root.appending(path: "traversal.tar")
        try makeTar(entries: [(.init(name: "../escape", type: "0", link: nil), Data("x".utf8))]).write(to: traversal)
        let validator = AppleKernelArchiveValidator()

        await #expect(throws: KernelAdapterError.archiveTraversal) {
            try await validator.validate(archive: traversal, binaryPath: "opt/kernel")
        }

        let symlink = root.appending(path: "symlink.tar")
        try makeTar(entries: [
            (.init(name: "opt/kernel", type: "2", link: "../../../../etc/passwd"), Data())
        ]).write(to: symlink)
        await #expect(throws: KernelAdapterError.unsafeKernelSymlink) {
            try await validator.validate(archive: symlink, binaryPath: "opt/kernel")
        }
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".mc-kernel-adapter-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private struct TarEntry {
        let name: String
        let type: Character
        let link: String?
    }

    private func makeTar(entries: [(TarEntry, Data)]) -> Data {
        var archive = Data()
        for (entry, contents) in entries {
            var header = Data(repeating: 0, count: 512)
            write(entry.name, into: &header, at: 0, length: 100)
            write("0000644\0", into: &header, at: 100, length: 8)
            write("0000000\0", into: &header, at: 108, length: 8)
            write("0000000\0", into: &header, at: 116, length: 8)
            write(String(format: "%011o\0", contents.count), into: &header, at: 124, length: 12)
            write("00000000000\0", into: &header, at: 136, length: 12)
            write("        ", into: &header, at: 148, length: 8)
            write(String(entry.type), into: &header, at: 156, length: 1)
            if let link = entry.link {
                write(link, into: &header, at: 157, length: 100)
            }
            write("ustar\0", into: &header, at: 257, length: 6)
            write("00", into: &header, at: 263, length: 2)
            let checksum = header.reduce(0) { $0 + Int($1) }
            write(String(format: "%06o\0 ", checksum), into: &header, at: 148, length: 8)
            archive.append(header)
            archive.append(contents)
            let padding = (512 - contents.count % 512) % 512
            archive.append(Data(repeating: 0, count: padding))
        }
        archive.append(Data(repeating: 0, count: 1024))
        return archive
    }

    private func write(_ value: String, into data: inout Data, at offset: Int, length: Int) {
        let bytes = Array(value.utf8.prefix(length))
        data.replaceSubrange(offset ..< offset + bytes.count, with: bytes)
    }
}

private actor FakeKernelBackend: KernelBackend {
    struct Install: Equatable, Sendable {
        let url: URL
        let platform: String
        let force: Bool
    }

    struct ArchiveInstall: Equatable, Sendable {
        let url: URL
        let binaryPath: String
        let platform: String
        let force: Bool
    }

    var binaryInstalls: [Install] = []
    var archiveInstalls: [ArchiveInstall] = []
    let recommendedDescriptor: KernelArchiveDescriptor?
    var recommendedCount = 0

    init(recommendedDescriptor: KernelArchiveDescriptor? = nil) {
        self.recommendedDescriptor = recommendedDescriptor
    }

    func recommended(platform: String) async throws -> KernelArchiveDescriptor {
        recommendedCount += 1
        return recommendedDescriptor ?? .pinnedKata328(platform: platform)
    }

    func installBinary(url: URL, platform: String, force: Bool) async throws -> KernelSummary {
        binaryInstalls.append(.init(url: url, platform: platform, force: force))
        return .init(identifier: url.path, platform: platform)
    }

    func installArchive(url: URL, binaryPath: String, platform: String, force: Bool) async throws -> KernelSummary {
        archiveInstalls.append(.init(url: url, binaryPath: binaryPath, platform: platform, force: force))
        return .init(identifier: binaryPath, platform: platform)
    }
}

private actor RecordingKernelDownloader: KernelDownloading {
    let data: Data
    var downloadCount = 0

    init(data: Data) {
        self.data = data
    }

    func download(from _: URL, to destination: URL, allowedHosts _: Set<String>) async throws {
        downloadCount += 1
        try data.write(to: destination)
    }
}

private struct ForbiddenKernelDownloader: KernelDownloading {
    func download(from _: URL, to _: URL, allowedHosts _: Set<String>) async throws {
        Issue.record("local kernel operation attempted a network download")
    }
}

private actor RecordingKernelArchiveValidator: KernelArchiveValidating {
    var validatedPaths: [String] = []

    func validate(archive _: URL, binaryPath: String) async throws {
        validatedPaths.append(binaryPath)
    }
}

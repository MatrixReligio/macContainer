import Foundation
import MCModel
@testable import MCTemplates
import Testing

@Suite("Custom template store")
struct TemplateStoreTests {
    @Test func `round trips without secrets`() async throws {
        let fileSystem = InMemoryTemplateFileSystem()
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)
        let document = TemplateDocument.fixture

        try await store.save(document)

        #expect(try await store.load(id: document.id) == document)
    }

    @Test func `rejects secret fields before write`() async throws {
        let fileSystem = InMemoryTemplateFileSystem()
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)
        let document = TemplateDocument.fixture.setting("registryPassword", to: .secret("value"))

        await #expect(throws: TemplateStoreError.secretField("registryPassword")) {
            try await store.save(document)
        }
        #expect(await fileSystem.snapshot().isEmpty)
    }

    @Test func `rejects disguised credentials and private key material before write`() async {
        let fileSystem = InMemoryTemplateFileSystem()
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)
        let unsafeValues: [(String, FieldValue)] = [
            ("password", .string("mis-typed credential")),
            ("environment", .keyValues([KeyValue(key: "API_TOKEN", value: "credential")])),
            ("notes", .string("-----BEGIN PRIVATE KEY-----\ncredential\n-----END PRIVATE KEY-----")),
            ("headers", .strings(["Authorization: Bearer credential"])),
            ("registryConfig", .string(#"{"auth":"Y3JlZGVudGlhbA=="}"#))
        ]

        for (id, value) in unsafeValues {
            await #expect(throws: TemplateStoreError.secretField(id)) {
                try await store.save(.fixture.setting(id, to: value))
            }
        }
        #expect(await fileSystem.snapshot().isEmpty)
    }

    @Test func `rejects disguised credentials when loading imported bytes`() async throws {
        let document = TemplateDocument.fixture.setting("password", to: .string("mis-typed credential"))
        let encoded = try JSONEncoder().encode(document)
        let fileSystem = InMemoryTemplateFileSystem(initial: ["/templates/id.json": encoded])
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)

        await #expect(throws: TemplateStoreError.secretField("password")) {
            try await store.load(id: "id")
        }
        #expect(await fileSystem.snapshot()["/templates/id.json"] == encoded)
    }

    @Test func `does not block ordinary words that merely contain a sensitive substring`() async throws {
        let fileSystem = InMemoryTemplateFileSystem()
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)
        let document = TemplateDocument.fixture.setting(
            "image",
            to: .string("ghcr.io/example/tokenizer-authorization-service:latest")
        )

        try await store.save(document)

        #expect(try await store.load(id: document.id) == document)
    }

    @Test func `failed replacement preserves previous document`() async throws {
        let old = Data("old".utf8)
        let fileSystem = InMemoryTemplateFileSystem(
            failWrite: true,
            initial: ["/templates/id.json": old]
        )
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)

        await #expect(throws: TestFileSystemError.replacementFailed) {
            try await store.save(.fixture)
        }
        #expect(await fileSystem.snapshot()["/templates/id.json"] == old)
    }

    @Test func `rejects unsafe document I ds before file access`() async {
        let fileSystem = InMemoryTemplateFileSystem()
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)
        let invalidIDs = ["", "../escape", "Uppercase", "-leading", "slash/name", String(repeating: "a", count: 65)]

        for id in invalidIDs {
            let document = TemplateDocument.fixture.withID(id)
            await #expect(throws: TemplateStoreError.invalidDocumentID(id)) {
                try await store.save(document)
            }
        }
        #expect(await fileSystem.snapshot().isEmpty)
    }

    @Test func `encoding and listing are deterministic`() async throws {
        let fileSystem = InMemoryTemplateFileSystem()
        let store = TemplateStore(root: URL(fileURLWithPath: "/templates"), fileSystem: fileSystem)
        let first = TemplateDocument.fixture.withID("alpha")
        let second = TemplateDocument.fixture.withID("beta")

        try await store.save(second)
        try await store.save(first)
        let firstEncoding = try #require(await fileSystem.snapshot()["/templates/alpha.json"])
        try await store.save(first)
        let secondEncoding = try #require(await fileSystem.snapshot()["/templates/alpha.json"])

        #expect(firstEncoding == secondEncoding)
        #expect(try await store.list().map(\.id) == ["alpha", "beta"])

        try await store.remove(id: "alpha")
        #expect(try await store.list().map(\.id) == ["beta"])
    }

    @Test func `local file system uses private atomic files and cleans temporary state`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainerTemplateStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemplateStore(root: root, fileSystem: LocalTemplateFileSystem())

        try await store.save(.fixture.withID("real"))
        try await store.save(.fixture.withID("real").withName("Updated"))

        let file = root.appendingPathComponent("real.json", isDirectory: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = try #require(attributes[.posixPermissions] as? Int)
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(permissions & 0o777 == 0o600)
        #expect(entries == ["real.json"])
        #expect(try await store.load(id: "real") == .fixture.withID("real").withName("Updated"))

        try FileManager.default.removeItem(at: root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

private extension TemplateDocument {
    static var fixture: Self {
        TemplateDocument(
            schemaVersion: 2,
            id: "id",
            name: "Development",
            operationID: "core.run",
            fields: [
                "image": DraftField(value: .string("alpine:latest"), source: .userOverride),
                "cpus": DraftField(value: .integer(2), source: .hostRecommendation)
            ]
        )
    }

    func setting(_ parameterID: String, to value: FieldValue) -> Self {
        var copy = self
        copy.fields[parameterID] = DraftField(value: value, source: .userOverride)
        return copy
    }

    func withID(_ id: String) -> Self {
        TemplateDocument(
            schemaVersion: schemaVersion,
            id: id,
            name: name,
            operationID: operationID,
            fields: fields
        )
    }

    func withName(_ name: String) -> Self {
        TemplateDocument(
            schemaVersion: schemaVersion,
            id: id,
            name: name,
            operationID: operationID,
            fields: fields
        )
    }
}

private enum TestFileSystemError: Error {
    case replacementFailed
}

private actor InMemoryTemplateFileSystem: TemplateFileSystem {
    private var files: [String: Data]
    private let failWrite: Bool

    init(failWrite: Bool = false, initial: [String: Data] = [:]) {
        self.failWrite = failWrite
        files = initial
    }

    func read(_ url: URL) throws -> Data {
        guard let data = files[url.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return data
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        if failWrite {
            throw TestFileSystemError.replacementFailed
        }
        files[url.path] = data
    }

    func list(_ root: URL) -> [URL] {
        files.keys
            .filter { URL(fileURLWithPath: $0).deletingLastPathComponent().path == root.path }
            .map { URL(fileURLWithPath: $0) }
    }

    func remove(_ url: URL) {
        files.removeValue(forKey: url.path)
    }

    func quarantine(_ url: URL) -> URL {
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(".quarantine/\(url.lastPathComponent).corrupt")
        files[destination.path] = files.removeValue(forKey: url.path)
        return destination
    }

    func snapshot() -> [String: Data] {
        files
    }
}

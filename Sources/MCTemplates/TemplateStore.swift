import Darwin
import Foundation

public protocol TemplateFileSystem: Sendable {
    func read(_ url: URL) async throws -> Data
    func writeAtomically(_ data: Data, to url: URL) async throws
    func list(_ root: URL) async throws -> [URL]
    func remove(_ url: URL) async throws
}

public enum TemplateStoreError: Error, Equatable, Sendable {
    case invalidDocumentID(String)
    case secretField(String)
    case unsupportedSchemaVersion(Int)
    case fileOutsideRoot(String)
}

public actor TemplateStore {
    private let root: URL
    private let fileSystem: any TemplateFileSystem

    public init(root: URL, fileSystem: any TemplateFileSystem) {
        self.root = root.standardizedFileURL
        self.fileSystem = fileSystem
    }

    public func save(_ document: TemplateDocument) async throws {
        try validateDocumentID(document.id)
        guard document.schemaVersion == TemplateDocument.currentSchemaVersion else {
            throw TemplateStoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        if let secretField = document.fields.keys.sorted().first(where: {
            document.fields[$0]?.value.containsSecret == true
        }) {
            throw TemplateStoreError.secretField(secretField)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try await fileSystem.writeAtomically(data, to: documentURL(id: document.id))
    }

    public func load(id: String) async throws -> TemplateDocument {
        let data = try await fileSystem.read(documentURL(id: id))
        let document = try JSONDecoder().decode(TemplateDocument.self, from: data)
        guard document.id == id else {
            throw TemplateStoreError.invalidDocumentID(document.id)
        }
        guard document.schemaVersion == TemplateDocument.currentSchemaVersion else {
            throw TemplateStoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }

    public func list() async throws -> [TemplateDocument] {
        let rootPath = root.path
        let urls = try await fileSystem.list(root)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var documents: [TemplateDocument] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            guard standardized.deletingLastPathComponent().path == rootPath else {
                throw TemplateStoreError.fileOutsideRoot(standardized.path)
            }
            let id = standardized.deletingPathExtension().lastPathComponent
            let document = try await load(id: id)
            documents.append(document)
        }
        return documents
    }

    public func remove(id: String) async throws {
        try await fileSystem.remove(documentURL(id: id))
    }

    private func documentURL(id: String) throws -> URL {
        try validateDocumentID(id)
        return root.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func validateDocumentID(_ id: String) throws {
        let bytes = Array(id.utf8)
        guard
            (1 ... 64).contains(bytes.count),
            let first = bytes.first,
            first.isASCIILowercaseOrDigit,
            bytes.allSatisfy({ $0.isASCIILowercaseOrDigit || $0 == 45 })
        else {
            throw TemplateStoreError.invalidDocumentID(id)
        }
    }
}

public struct LocalTemplateFileSystem: TemplateFileSystem {
    public init() {}

    public func read(_ url: URL) async throws -> Data {
        try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    public func writeAtomically(_ data: Data, to url: URL) async throws {
        let fileManager = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)

        let temporary = parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try synchronizeDirectory(parent)
    }

    public func list(_ root: URL) async throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
    }

    public func remove(_ url: URL) async throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
        try synchronizeDirectory(url.deletingLastPathComponent())
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw posixError()
        }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw posixError()
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private extension UInt8 {
    var isASCIILowercaseOrDigit: Bool {
        (97 ... 122).contains(self) || (48 ... 57).contains(self)
    }
}

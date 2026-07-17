import Darwin
import Foundation
import MCCompatibility

public struct BlockedVersionRecord: Codable, Equatable, Sendable {
    public let runtimeVersion: String
    public let appVersion: String
    public let catalogRevision: String
    public let attestationID: String
    public let failedProbeID: ProbeID?
    public let timestamp: Date

    public init(
        runtimeVersion: String,
        appVersion: String,
        catalogRevision: String,
        attestationID: String,
        failedProbeID: ProbeID?,
        timestamp: Date
    ) {
        self.runtimeVersion = runtimeVersion
        self.appVersion = appVersion
        self.catalogRevision = catalogRevision
        self.attestationID = attestationID
        self.failedProbeID = failedProbeID
        self.timestamp = timestamp
    }
}

public enum BlockedVersionStoreError: Error, Equatable, Sendable {
    case corruptStorage
    case ioFailure
    case unsafeStorage
}

public actor BlockedVersionStore {
    private struct Storage: Codable {
        let schemaVersion: Int
        var records: [BlockedVersionRecord]
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public init() {
        self.init(fileURL: Self.defaultURL)
    }

    public func record(_ record: BlockedVersionRecord) throws {
        var storage = try load()
        storage.records.removeAll { $0.runtimeVersion == record.runtimeVersion }
        storage.records.append(record)
        storage.records.sort { $0.runtimeVersion < $1.runtimeVersion }
        try save(storage)
    }

    public func record(for runtimeVersion: String) throws -> BlockedVersionRecord? {
        try load().records.first { $0.runtimeVersion == runtimeVersion }
    }

    public func blockingAttestationID(
        for entry: CompatibilityEntry,
        catalogRevision: String
    ) throws -> String? {
        var storage = try load()
        guard let record = storage.records.first(where: { $0.runtimeVersion == entry.runtimeVersion }) else {
            return nil
        }
        let explicitlySuperseded = catalogRevision != record.catalogRevision &&
            entry.attestation.id != record.attestationID &&
            entry.supersedesBlockedAttestationIDs.contains(record.attestationID)
        guard explicitlySuperseded else {
            return record.attestationID
        }
        storage.records.removeAll { $0.runtimeVersion == entry.runtimeVersion }
        try save(storage)
        return nil
    }

    private func load() throws -> Storage {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Storage(schemaVersion: 1, records: [])
        }
        let data = try readSecureFile()
        do {
            let storage = try decoder.decode(Storage.self, from: data)
            guard storage.schemaVersion == 1,
                  Set(storage.records.map(\.runtimeVersion)).count == storage.records.count
            else {
                throw BlockedVersionStoreError.corruptStorage
            }
            return storage
        } catch let error as BlockedVersionStoreError {
            throw error
        } catch {
            throw BlockedVersionStoreError.corruptStorage
        }
    }

    private func readSecureFile() throws -> Data {
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw BlockedVersionStoreError.unsafeStorage
            }
            throw BlockedVersionStoreError.ioFailure
        }
        defer { Darwin.close(descriptor) }
        try validate(descriptor)

        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw BlockedVersionStoreError.ioFailure
            }
            guard count > 0 else { break }
            guard bytes.count + count <= 1_048_576 else {
                throw BlockedVersionStoreError.corruptStorage
            }
            bytes.append(buffer, count: count)
        }
        return bytes
    }

    private func save(_ storage: Storage) throws {
        try prepareParent()
        let data = try encoder.encode(storage)
        guard data.count <= 1_048_576 else {
            throw BlockedVersionStoreError.corruptStorage
        }
        let temporary = fileURL.deletingLastPathComponent()
            .appending(path: ".blocked-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else { throw BlockedVersionStoreError.ioFailure }
        do {
            try write(data, to: descriptor)
            guard Darwin.fsync(descriptor) == 0 else { throw BlockedVersionStoreError.ioFailure }
            guard Darwin.close(descriptor) == 0 else { throw BlockedVersionStoreError.ioFailure }
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        guard Darwin.rename(temporary.path, fileURL.path) == 0 else {
            throw BlockedVersionStoreError.ioFailure
        }
        try synchronizeParent()
    }

    private func prepareParent() throws {
        let parent = fileURL.deletingLastPathComponent()
        var metadata = stat()
        if Darwin.lstat(parent.path, &metadata) == 0 {
            guard (metadata.st_mode & S_IFMT) == S_IFDIR, metadata.st_uid == getuid() else {
                throw BlockedVersionStoreError.unsafeStorage
            }
        } else if errno == ENOENT {
            do {
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw BlockedVersionStoreError.ioFailure
            }
        } else {
            throw BlockedVersionStoreError.ioFailure
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        } catch {
            throw BlockedVersionStoreError.ioFailure
        }
    }

    private func validate(_ descriptor: Int32) throws {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw BlockedVersionStoreError.ioFailure
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == getuid(),
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0
        else {
            throw BlockedVersionStoreError.unsafeStorage
        }
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw BlockedVersionStoreError.ioFailure
                }
                offset += count
            }
        }
    }

    private func synchronizeParent() throws {
        let descriptor = Darwin.open(fileURL.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw BlockedVersionStoreError.ioFailure }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw BlockedVersionStoreError.ioFailure }
    }

    private static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "container.matrixreligio.com/Updates", directoryHint: .isDirectory)
            .appending(path: "blocked-versions.json")
    }
}

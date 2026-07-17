import Darwin
import Foundation

public actor PersistentAttestationReplayStore: AttestationReplayChecking {
    private struct Record: Codable {
        let nonce: UUID
        let issuedAt: Date
    }

    private struct Storage: Codable {
        let schemaVersion: Int
        var records: [Record]
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func accept(nonce: UUID, issuedAt: Date) throws -> Bool {
        var storage = try load()
        guard storage.records.contains(where: { $0.nonce == nonce }) == false else {
            return false
        }
        storage.records.append(.init(nonce: nonce, issuedAt: issuedAt))
        storage.records.sort { $0.issuedAt < $1.issuedAt }
        if storage.records.count > 10000 {
            storage.records.removeFirst(storage.records.count - 10000)
        }
        try save(storage)
        return true
    }

    private func load() throws -> Storage {
        guard let descriptor = try openExisting() else {
            return Storage(schemaVersion: 1, records: [])
        }
        defer { Darwin.close(descriptor) }
        return try decode(secureRead(descriptor))
    }

    private func openExisting() throws -> Int32? {
        var metadata = stat()
        if Darwin.lstat(fileURL.path, &metadata) != 0 {
            guard errno == ENOENT else { throw AttestationVerificationError.replayStoreUnsafe }
            return nil
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw AttestationVerificationError.replayStoreUnsafe
        }
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw AttestationVerificationError.replayStoreUnsafe }
        do {
            try validate(descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func secureRead(_ descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw AttestationVerificationError.replayStoreUnsafe
            }
            guard count > 0 else { break }
            guard data.count + count <= 2_000_000 else {
                throw AttestationVerificationError.replayStoreCorrupt
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private func decode(_ data: Data) throws -> Storage {
        do {
            let storage = try decoder.decode(Storage.self, from: data)
            guard storage.schemaVersion == 1,
                  Set(storage.records.map(\.nonce)).count == storage.records.count,
                  storage.records.count <= 10000
            else {
                throw AttestationVerificationError.replayStoreCorrupt
            }
            return storage
        } catch let error as AttestationVerificationError {
            throw error
        } catch {
            throw AttestationVerificationError.replayStoreCorrupt
        }
    }

    private func save(_ storage: Storage) throws {
        try prepareParent()
        try validateExistingTarget()
        let data = try encoder.encode(storage)
        guard data.count <= 2_000_000 else { throw AttestationVerificationError.replayStoreCorrupt }
        let temporary = fileURL.deletingLastPathComponent()
            .appending(path: ".attestation-replay-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else { throw AttestationVerificationError.replayStoreUnsafe }
        do {
            try data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < data.count {
                    let count = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                    guard count >= 0 else {
                        if errno == EINTR {
                            continue
                        }
                        throw AttestationVerificationError.replayStoreUnsafe
                    }
                    offset += count
                }
            }
            guard Darwin.fsync(descriptor) == 0,
                  Darwin.close(descriptor) == 0,
                  Darwin.rename(temporary.path, fileURL.path) == 0
            else {
                throw AttestationVerificationError.replayStoreUnsafe
            }
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func prepareParent() throws {
        let parent = fileURL.deletingLastPathComponent()
        var metadata = stat()
        if Darwin.lstat(parent.path, &metadata) == 0 {
            guard (metadata.st_mode & S_IFMT) == S_IFDIR,
                  metadata.st_uid == getuid()
            else {
                throw AttestationVerificationError.replayStoreUnsafe
            }
        } else if errno == ENOENT {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            throw AttestationVerificationError.replayStoreUnsafe
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
    }

    private func validateExistingTarget() throws {
        var metadata = stat()
        guard Darwin.lstat(fileURL.path, &metadata) == 0 else {
            if errno == ENOENT {
                return
            }
            throw AttestationVerificationError.replayStoreUnsafe
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == getuid(),
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0
        else {
            throw AttestationVerificationError.replayStoreUnsafe
        }
    }

    private func validate(_ descriptor: Int32) throws {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == getuid(),
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0
        else {
            throw AttestationVerificationError.replayStoreUnsafe
        }
    }
}

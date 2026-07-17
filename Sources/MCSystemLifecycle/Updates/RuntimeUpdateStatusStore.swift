import Darwin
import Foundation

public struct PersistedRuntimeUpdateStatus: Codable, Equatable, Sendable {
    public let state: RuntimeUpdateState
    public let updatedAt: Date

    public init(state: RuntimeUpdateState, updatedAt: Date) {
        self.state = state
        self.updatedAt = updatedAt
    }
}

public protocol RuntimeUpdateStatusStoring: Sendable {
    func load() async throws -> PersistedRuntimeUpdateStatus?
    func save(_ status: PersistedRuntimeUpdateStatus) async throws
}

public enum RuntimeUpdateStatusStoreError: Error, Equatable, Sendable {
    case corruptStorage
    case unsafeStorage
}

public actor RuntimeUpdateStatusStore: RuntimeUpdateStatusStoring, RuntimeUpdateStateSink {
    private struct Storage: Codable {
        let schemaVersion: Int
        let status: PersistedRuntimeUpdateStatus
    }

    private static let maximumBytes = 64 * 1024
    private let fileURL: URL
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL = RuntimeUpdateStatusStore.defaultURL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.now = now
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> PersistedRuntimeUpdateStatus? {
        guard try existingFileIsSafe() else { return nil }
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RuntimeUpdateStatusStoreError.unsafeStorage }
        defer { Darwin.close(descriptor) }
        let data = try read(descriptor)
        do {
            let storage = try decoder.decode(Storage.self, from: data)
            guard storage.schemaVersion == 1 else {
                throw RuntimeUpdateStatusStoreError.corruptStorage
            }
            return storage.status
        } catch let error as RuntimeUpdateStatusStoreError {
            throw error
        } catch {
            throw RuntimeUpdateStatusStoreError.corruptStorage
        }
    }

    public func save(_ status: PersistedRuntimeUpdateStatus) throws {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/") else {
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
        let parent = fileURL.deletingLastPathComponent()
        try ensurePrivateDirectory(parent.deletingLastPathComponent())
        try ensurePrivateDirectory(parent)
        _ = try existingFileIsSafe()
        let data = try encoder.encode(Storage(schemaVersion: 1, status: status))
        guard data.count <= Self.maximumBytes else {
            throw RuntimeUpdateStatusStoreError.corruptStorage
        }

        let directory = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directory >= 0 else { throw RuntimeUpdateStatusStoreError.unsafeStorage }
        defer { Darwin.close(directory) }
        let temporaryName = ".status-\(UUID().uuidString).tmp"
        let descriptor = temporaryName.withCString {
            Darwin.openat(directory, $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else { throw RuntimeUpdateStatusStoreError.unsafeStorage }
        var removeTemporary = true
        defer {
            Darwin.close(descriptor)
            if removeTemporary {
                _ = temporaryName.withCString { Darwin.unlinkat(directory, $0, 0) }
            }
        }
        try write(data, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else {
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
        let renamed = temporaryName.withCString { temporary in
            fileURL.lastPathComponent.withCString { destination in
                Darwin.renameat(directory, temporary, directory, destination)
            }
        }
        guard renamed == 0, Darwin.fsync(directory) == 0 else {
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
        removeTemporary = false
        guard try existingFileIsSafe() else {
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
    }

    public func publish(_ state: RuntimeUpdateState) {
        try? save(.init(state: state, updatedAt: now()))
    }

    private func existingFileIsSafe() throws -> Bool {
        var status = stat()
        guard Darwin.lstat(fileURL.path, &status) == 0 else {
            if errno == ENOENT {
                return false
            }
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size <= Self.maximumBytes
        else {
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
        return true
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        var status = stat()
        if Darwin.lstat(directory.path, &status) != 0 {
            guard errno == ENOENT, Darwin.mkdir(directory.path, 0o700) == 0,
                  Darwin.lstat(directory.path, &status) == 0
            else {
                throw RuntimeUpdateStatusStoreError.unsafeStorage
            }
        }
        guard status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0
        else {
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
    }

    private func read(_ descriptor: Int32) throws -> Data {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size <= Self.maximumBytes
        else {
            throw RuntimeUpdateStatusStoreError.unsafeStorage
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw RuntimeUpdateStatusStoreError.unsafeStorage
            }
            guard count > 0 else { break }
            guard data.count + count <= Self.maximumBytes else {
                throw RuntimeUpdateStatusStoreError.corruptStorage
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw RuntimeUpdateStatusStoreError.unsafeStorage
                }
                offset += count
            }
        }
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("status.json", isDirectory: false)
    }
}

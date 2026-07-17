import Darwin
import Foundation

public enum UpdateAgentFileError: Error, Equatable, Sendable {
    case corruptState
    case unsafeState
}

public actor PrivateUpdateAgentStateStore: UpdateAgentStateStoring {
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

    public init() {
        self.init(fileURL: Self.defaultURL)
    }

    public func load() throws -> UpdateAgentPersistentState {
        guard try validateExistingFile() else {
            return UpdateAgentPersistentState()
        }
        do {
            return try decoder.decode(
                UpdateAgentPersistentState.self,
                from: readSecurely()
            )
        } catch let error as UpdateAgentFileError {
            throw error
        } catch {
            throw UpdateAgentFileError.corruptState
        }
    }

    public func save(_ state: UpdateAgentPersistentState) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var parentMetadata = stat()
        guard Darwin.lstat(parent.path, &parentMetadata) == 0,
              (parentMetadata.st_mode & S_IFMT) == S_IFDIR,
              parentMetadata.st_uid == getuid()
        else {
            throw UpdateAgentFileError.unsafeState
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        _ = try validateExistingFile()
        let data = try encoder.encode(state)
        guard data.count <= 1_048_576 else { throw UpdateAgentFileError.corruptState }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func validateExistingFile() throws -> Bool {
        var metadata = stat()
        guard Darwin.lstat(fileURL.path, &metadata) == 0 else {
            if errno == ENOENT {
                return false
            }
            throw UpdateAgentFileError.unsafeState
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == getuid(),
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0
        else {
            throw UpdateAgentFileError.unsafeState
        }
        return true
    }

    private func readSecurely() throws -> Data {
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw UpdateAgentFileError.unsafeState }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == getuid(),
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0,
              metadata.st_size <= 1_048_576
        else {
            throw UpdateAgentFileError.unsafeState
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw UpdateAgentFileError.unsafeState
            }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "container.matrixreligio.com/Updates", directoryHint: .isDirectory)
            .appending(path: "agent-state.json")
    }
}

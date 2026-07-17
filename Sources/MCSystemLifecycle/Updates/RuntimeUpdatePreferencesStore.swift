import Darwin
import Foundation

public struct RuntimeUpdatePreferences: Codable, Equatable, Sendable {
    public let automaticallyChecks: Bool
    public let mode: RuntimeUpdateMode
    public let consentVersion: Int?

    public init(
        automaticallyChecks: Bool,
        mode: RuntimeUpdateMode,
        consentVersion: Int?
    ) {
        self.automaticallyChecks = automaticallyChecks
        self.mode = mode
        self.consentVersion = consentVersion
    }

    public static let safeDefaults = Self(
        automaticallyChecks: true,
        mode: .checkOnly,
        consentVersion: nil
    )
}

public protocol RuntimeUpdatePreferencesPersisting: Sendable {
    func load() throws -> RuntimeUpdatePreferences
    func save(_ preferences: RuntimeUpdatePreferences) throws
}

public enum RuntimeUpdatePreferencesStoreError: Error, Equatable, Sendable {
    case corruptStorage
    case invalidPreferences
    case unsafeStorage
}

public struct RuntimeUpdatePreferencesStore: RuntimeUpdatePreferencesPersisting, Sendable {
    private struct Storage: Codable {
        let schemaVersion: Int
        let preferences: RuntimeUpdatePreferences
    }

    private static let maximumBytes = 64 * 1024
    private let fileURL: URL

    public init(fileURL: URL = Self.defaultURL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    public func load() throws -> RuntimeUpdatePreferences {
        guard try existingFileIsSafe() else { return .safeDefaults }
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RuntimeUpdatePreferencesStoreError.unsafeStorage }
        defer { Darwin.close(descriptor) }
        let data = try Self.readSecurely(descriptor)
        let storage: Storage
        do {
            storage = try JSONDecoder().decode(Storage.self, from: data)
        } catch {
            throw RuntimeUpdatePreferencesStoreError.corruptStorage
        }
        guard storage.schemaVersion == 1 else {
            throw RuntimeUpdatePreferencesStoreError.corruptStorage
        }
        try Self.validate(storage.preferences)
        return storage.preferences
    }

    public func save(_ preferences: RuntimeUpdatePreferences) throws {
        try Self.validate(preferences)
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/") else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        let parent = fileURL.deletingLastPathComponent()
        try ensurePrivateDirectory(parent.deletingLastPathComponent())
        try ensurePrivateDirectory(parent)
        _ = try existingFileIsSafe()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Storage(schemaVersion: 1, preferences: preferences))
        guard data.count <= Self.maximumBytes else {
            throw RuntimeUpdatePreferencesStoreError.corruptStorage
        }

        let directoryDescriptor = Darwin.open(
            parent.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        defer { Darwin.close(directoryDescriptor) }
        let temporaryName = ".preferences-\(UUID().uuidString).tmp"
        let descriptor = temporaryName.withCString {
            Darwin.openat(directoryDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        var removeTemporary = true
        defer {
            Darwin.close(descriptor)
            if removeTemporary {
                _ = temporaryName.withCString { Darwin.unlinkat(directoryDescriptor, $0, 0) }
            }
        }
        try Self.write(data, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        let renamed = temporaryName.withCString { temporary in
            fileURL.lastPathComponent.withCString { destination in
                Darwin.renameat(directoryDescriptor, temporary, directoryDescriptor, destination)
            }
        }
        guard renamed == 0, Darwin.fsync(directoryDescriptor) == 0 else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        removeTemporary = false
        guard try existingFileIsSafe() else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
    }

    private func existingFileIsSafe() throws -> Bool {
        var status = stat()
        guard Darwin.lstat(fileURL.path, &status) == 0 else {
            if errno == ENOENT {
                return false
            }
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size <= Self.maximumBytes
        else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        return true
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        var status = stat()
        if Darwin.lstat(directory.path, &status) != 0 {
            guard errno == ENOENT, Darwin.mkdir(directory.path, 0o700) == 0,
                  Darwin.lstat(directory.path, &status) == 0
            else {
                throw RuntimeUpdatePreferencesStoreError.unsafeStorage
            }
        }
        guard status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0
        else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
    }

    private static func validate(_ preferences: RuntimeUpdatePreferences) throws {
        switch preferences.mode {
        case .automaticWhenIdle:
            guard preferences.automaticallyChecks,
                  preferences.consentVersion == RuntimeUpdatePolicy.currentConsentVersion
            else {
                throw RuntimeUpdatePreferencesStoreError.invalidPreferences
            }
        case .downloadAndNotify:
            guard preferences.automaticallyChecks, preferences.consentVersion == nil else {
                throw RuntimeUpdatePreferencesStoreError.invalidPreferences
            }
        case .checkOnly:
            guard preferences.consentVersion == nil else {
                throw RuntimeUpdatePreferencesStoreError.invalidPreferences
            }
        }
    }

    private static func readSecurely(_ descriptor: Int32) throws -> Data {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size <= maximumBytes
        else {
            throw RuntimeUpdatePreferencesStoreError.unsafeStorage
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw RuntimeUpdatePreferencesStoreError.unsafeStorage
            }
            guard count > 0 else { break }
            guard data.count + count <= maximumBytes else {
                throw RuntimeUpdatePreferencesStoreError.corruptStorage
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw RuntimeUpdatePreferencesStoreError.unsafeStorage
                }
                offset += count
            }
        }
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
    }
}

import Darwin
import Foundation

public enum TestArtifact: Codable, Equatable, Hashable, Sendable {
    case container(String)
    case image(String)
    case network(String)
    case volume(String)
    case machine(String)
    case registryCredential(String)
    case runtimePackage(String)
    case rollbackPoint(UUID)
    case resolver(String)
    case packetFilterAnchor(String)
    case temporaryDirectory(String)
    case file(String)
    case keychain(String)
    case launchService(String)
    case resultBundle(String)

    public var fileSystemPath: String? {
        switch self {
        case let .runtimePackage(path), let .temporaryDirectory(path), let .file(path), let .resultBundle(path):
            path
        default:
            nil
        }
    }

    var isTemporaryDirectory: Bool {
        if case .temporaryDirectory = self {
            true
        } else {
            false
        }
    }

    var ownsFileSystemDescendants: Bool {
        switch self {
        case .temporaryDirectory, .resultBundle:
            true
        default:
            false
        }
    }
}

public enum CleanupState: String, Codable, Equatable, Sendable {
    case planned
    case created
    case removed
    case verifiedAbsent
}

public struct CleanupEvent: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runID: UUID
    public let sequence: Int
    public let artifact: TestArtifact
    public let state: CleanupState

    public init(
        schemaVersion: Int = 1,
        runID: UUID,
        sequence: Int,
        artifact: TestArtifact,
        state: CleanupState
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.sequence = sequence
        self.artifact = artifact
        self.state = state
    }
}

public protocol CleanupLedgerStorage: Sendable {
    func append(_ event: CleanupEvent) async throws
    func load() async throws -> [CleanupEvent]
}

public enum CleanupLedgerError: Error, Equatable {
    case invalidTransition(from: CleanupState?, to: CleanupState)
    case duplicateArtifact
    case runIDMismatch
    case corruptLedger
    case unsupportedSchema(Int)
    case invalidSequence
    case unsafeStorage
}

public actor CleanupLedger {
    public let runID: UUID
    private let storage: any CleanupLedgerStorage
    private var states: [TestArtifact: CleanupState]
    private var nextSequence: Int

    public init(storage: any CleanupLedgerStorage, runID: UUID) {
        self.storage = storage
        self.runID = runID
        states = [:]
        nextSequence = 0
    }

    public static func recover(
        storage: any CleanupLedgerStorage,
        runID: UUID
    ) async throws -> CleanupLedger {
        let ledger = CleanupLedger(storage: storage, runID: runID)
        try await ledger.restore(await: storage.load())
        return ledger
    }

    public func state(of artifact: TestArtifact) -> CleanupState? {
        states[artifact]
    }

    public func plan(_ artifact: TestArtifact) async throws {
        guard states[artifact] == nil else {
            throw CleanupLedgerError.duplicateArtifact
        }
        try await transition(artifact, to: .planned)
    }

    public func markCreated(_ artifact: TestArtifact) async throws {
        try await transition(artifact, to: .created)
    }

    public func markRemoved(_ artifact: TestArtifact) async throws {
        try await transition(artifact, to: .removed)
    }

    public func markVerifiedAbsent(_ artifact: TestArtifact) async throws {
        try await transition(artifact, to: .verifiedAbsent)
    }

    public func allStates() -> [TestArtifact: CleanupState] {
        states
    }

    private func transition(_ artifact: TestArtifact, to state: CleanupState) async throws {
        let current = states[artifact]
        guard Self.isValidTransition(from: current, to: state) else {
            throw CleanupLedgerError.invalidTransition(from: current, to: state)
        }
        let event = CleanupEvent(
            runID: runID,
            sequence: nextSequence,
            artifact: artifact,
            state: state
        )
        try await storage.append(event)
        states[artifact] = state
        nextSequence += 1
    }

    private func restore(await events: [CleanupEvent]) throws {
        var restored: [TestArtifact: CleanupState] = [:]
        for (index, event) in events.enumerated() {
            guard event.schemaVersion == 1 else {
                throw CleanupLedgerError.unsupportedSchema(event.schemaVersion)
            }
            guard event.runID == runID else {
                throw CleanupLedgerError.runIDMismatch
            }
            guard event.sequence == index else {
                throw CleanupLedgerError.invalidSequence
            }
            let current = restored[event.artifact]
            guard Self.isValidTransition(from: current, to: event.state) else {
                throw CleanupLedgerError.corruptLedger
            }
            restored[event.artifact] = event.state
        }
        states = restored
        nextSequence = events.count
    }

    private static func isValidTransition(from current: CleanupState?, to next: CleanupState) -> Bool {
        switch (current, next) {
        case (nil, .planned), (.planned, .created), (.created, .removed), (.removed, .verifiedAbsent):
            true
        default:
            false
        }
    }
}

public actor FileCleanupLedgerStorage: CleanupLedgerStorage {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) throws {
        self.url = url.standardizedFileURL
        let descriptor = open(self.url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw CleanupLedgerError.unsafeStorage
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw CleanupLedgerError.unsafeStorage
        }
    }

    public func append(_ event: CleanupEvent) async throws {
        var data = try encoder.encode(event)
        data.append(0x0A)
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw CleanupLedgerError.unsafeStorage
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw CleanupLedgerError.unsafeStorage
        }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: written), bytes.count - written)
                guard count > 0 else {
                    throw CleanupLedgerError.unsafeStorage
                }
                written += count
            }
        }
        guard fsync(descriptor) == 0 else {
            throw CleanupLedgerError.unsafeStorage
        }
    }

    public func load() async throws -> [CleanupEvent] {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw CleanupLedgerError.unsafeStorage
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw CleanupLedgerError.unsafeStorage
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        guard data.isEmpty || data.last == 0x0A else {
            throw CleanupLedgerError.corruptLedger
        }
        do {
            return try data.split(separator: 0x0A).map { line in
                try decoder.decode(CleanupEvent.self, from: Data(line))
            }
        } catch is CleanupLedgerError {
            throw CleanupLedgerError.corruptLedger
        } catch {
            throw CleanupLedgerError.corruptLedger
        }
    }
}

import Darwin
import Foundation

public protocol LifecycleJournalStorage: Sendable {
    func load() async throws -> [LifecycleEvent]
    func append(_ event: LifecycleEvent) async throws
}

public enum LifecycleJournalError: Error, Equatable, Sendable {
    case activeTransaction(UUID)
    case corruptJournal
    case invalidTransition(from: LifecyclePhase, to: LifecyclePhase)
    case mismatchedAppliedAction
    case transactionAlreadyTerminal(UUID)
    case transactionNotFound(UUID)
    case unsafeJournal
}

public actor LifecycleJournal {
    private let storage: any LifecycleJournalStorage
    private let now: @Sendable () -> Date

    public init(
        storage: any LifecycleJournalStorage,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.storage = storage
        self.now = now
    }

    public static func live() -> LifecycleJournal {
        LifecycleJournal(storage: JSONLineLifecycleJournalStorage(fileURL: defaultJournalURL()))
    }

    public func begin(kind: LifecycleKind, targetVersion: String?) async throws -> UUID {
        let events = try await storage.load()
        if let active = activeTransaction(in: events) {
            throw LifecycleJournalError.activeTransaction(active)
        }
        let transactionID = UUID()
        let draft = LifecycleEventDraft(
            transactionID: transactionID,
            kind: kind,
            phase: .began,
            targetVersion: targetVersion,
            action: nil,
            failure: nil
        )
        try await append(draft, existingEvents: events)
        return transactionID
    }

    public func recordIntent(_ action: LifecycleAction, transactionID: UUID) async throws {
        try await transition(transactionID: transactionID, phase: .intent, action: action)
    }

    public func recordApplied(_ action: LifecycleAction, transactionID: UUID) async throws {
        try await transition(transactionID: transactionID, phase: .applied, action: action)
    }

    public func recordVerified(transactionID: UUID) async throws {
        try await transition(transactionID: transactionID, phase: .verified)
    }

    public func commit(transactionID: UUID) async throws {
        try await transition(transactionID: transactionID, phase: .committed)
    }

    public func recordRollingBack(_ action: LifecycleAction?, transactionID: UUID) async throws {
        try await transition(transactionID: transactionID, phase: .rollingBack, action: action)
    }

    public func recordRolledBack(transactionID: UUID) async throws {
        try await transition(transactionID: transactionID, phase: .rolledBack)
    }

    public func recordFailure(
        _ failure: RedactedLifecycleFailure,
        transactionID: UUID
    ) async throws {
        try await transition(transactionID: transactionID, phase: .failed, failure: failure)
    }

    public func events(for transactionID: UUID) async throws -> [LifecycleEvent] {
        try await storage.load().filter { $0.transactionID == transactionID }
    }

    public func allEvents() async throws -> [LifecycleEvent] {
        try await storage.load()
    }

    private func transition(
        transactionID: UUID,
        phase: LifecyclePhase,
        action: LifecycleAction? = nil,
        failure: RedactedLifecycleFailure? = nil
    ) async throws {
        let allEvents = try await storage.load()
        let transactionEvents = allEvents.filter { $0.transactionID == transactionID }
        guard let first = transactionEvents.first, let last = transactionEvents.last else {
            throw LifecycleJournalError.transactionNotFound(transactionID)
        }
        guard !last.phase.isTerminal else {
            throw LifecycleJournalError.transactionAlreadyTerminal(transactionID)
        }
        guard Self.isAllowedTransition(from: last.phase, to: phase) else {
            throw LifecycleJournalError.invalidTransition(from: last.phase, to: phase)
        }
        if phase == .applied {
            guard last.phase == .intent, last.action == action else {
                throw LifecycleJournalError.mismatchedAppliedAction
            }
        }
        let draft = LifecycleEventDraft(
            transactionID: transactionID,
            kind: first.kind,
            phase: phase,
            targetVersion: first.targetVersion,
            action: action,
            failure: failure
        )
        try await append(draft, existingEvents: allEvents)
    }

    private func append(
        _ draft: LifecycleEventDraft,
        existingEvents: [LifecycleEvent]
    ) async throws {
        let sequence = (existingEvents.last?.sequence ?? 0) + 1
        let event = LifecycleEvent(
            sequence: sequence,
            transactionID: draft.transactionID,
            kind: draft.kind,
            phase: draft.phase,
            targetVersion: draft.targetVersion,
            action: draft.action,
            failure: draft.failure,
            timestamp: now()
        )
        try await storage.append(event)
    }

    private func activeTransaction(in events: [LifecycleEvent]) -> UUID? {
        let latestByID = Dictionary(grouping: events, by: \.transactionID).compactMapValues(\.last)
        return latestByID.values
            .filter { !$0.phase.isTerminal }
            .min { $0.sequence < $1.sequence }?
            .transactionID
    }

    private static func isAllowedTransition(from: LifecyclePhase, to: LifecyclePhase) -> Bool {
        if to == .failed {
            return true
        }
        return switch (from, to) {
        case (.began, .intent), (.applied, .intent), (.verified, .intent),
             (.intent, .applied), (.applied, .verified), (.verified, .committed),
             (.applied, .committed), (.began, .committed),
             (.began, .rollingBack), (.intent, .rollingBack),
             (.applied, .rollingBack), (.verified, .rollingBack),
             (.rollingBack, .intent), (.rollingBack, .rolledBack), (.applied, .rolledBack):
            true
        default:
            false
        }
    }

    private static func defaultJournalURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("Lifecycle", isDirectory: true)
            .appendingPathComponent("journal.jsonl", isDirectory: false)
    }
}

private struct LifecycleEventDraft {
    let transactionID: UUID
    let kind: LifecycleKind
    let phase: LifecyclePhase
    let targetVersion: String?
    let action: LifecycleAction?
    let failure: RedactedLifecycleFailure?
}

public actor JSONLineLifecycleJournalStorage: LifecycleJournalStorage {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
    }

    public func load() throws -> [LifecycleEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try readSecurely()
            return try decodeAndValidate(data)
        } catch let error as LifecycleJournalError where error == .unsafeJournal {
            throw error
        } catch {
            try quarantineCorruptJournal()
            throw LifecycleJournalError.corruptJournal
        }
    }

    public func append(_ event: LifecycleEvent) throws {
        try prepareParent()
        let descriptor = Darwin.open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        try lockDescriptor(descriptor, type: Int16(F_WRLCK))
        defer { unlockDescriptor(descriptor) }
        try validateDescriptor(descriptor)

        let existing: [LifecycleEvent]
        do {
            existing = try decodeAndValidate(readAll(from: descriptor))
        } catch {
            throw LifecycleJournalError.corruptJournal
        }
        guard event.sequence == (existing.last?.sequence ?? 0) + 1 else {
            throw LifecycleJournalError.corruptJournal
        }
        guard Darwin.lseek(descriptor, 0, SEEK_END) >= 0 else { throw posixError() }
        var line = try encoder.encode(event)
        line.append(0x0A)
        try writeAll(line, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        try synchronizeDirectory(fileURL.deletingLastPathComponent())
    }

    private func readSecurely() throws -> Data {
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        try lockDescriptor(descriptor, type: Int16(F_RDLCK))
        defer { unlockDescriptor(descriptor) }
        try validateDescriptor(descriptor)

        return try readAll(from: descriptor)
    }

    private func readAll(from descriptor: Int32) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else { throw posixError() }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR {
                    continue
                }
                throw posixError()
            }
            guard count > 0 else { break }
            bytes.append(buffer, count: count)
        }
        return bytes
    }

    private func lockDescriptor(_ descriptor: Int32, type: Int16) throws {
        var lock = flock()
        lock.l_type = type
        lock.l_whence = Int16(SEEK_SET)
        while Darwin.fcntl(descriptor, F_SETLKW, &lock) != 0 {
            guard errno == EINTR else { throw posixError() }
        }
    }

    private func unlockDescriptor(_ descriptor: Int32) {
        var lock = flock()
        lock.l_type = Int16(F_UNLCK)
        lock.l_whence = Int16(SEEK_SET)
        _ = Darwin.fcntl(descriptor, F_SETLK, &lock)
    }

    private func decodeAndValidate(_ data: Data) throws -> [LifecycleEvent] {
        guard data.isEmpty || data.last == 0x0A else {
            throw LifecycleJournalError.corruptJournal
        }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false).dropLast()
        var events: [LifecycleEvent] = []
        events.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else { throw LifecycleJournalError.corruptJournal }
            let event = try decoder.decode(LifecycleEvent.self, from: Data(line))
            guard event.sequence == UInt64(index + 1) else {
                throw LifecycleJournalError.corruptJournal
            }
            events.append(event)
        }
        return events
    }

    private func prepareParent() throws {
        let parent = fileURL.deletingLastPathComponent()
        try preparePrivateDirectory(parent)
    }

    private func preparePrivateDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var status = stat()
        guard
            Darwin.lstat(directory.path, &status) == 0,
            status.st_mode & S_IFMT == S_IFDIR,
            status.st_uid == getuid()
        else {
            throw LifecycleJournalError.unsafeJournal
        }
        guard Darwin.chmod(directory.path, 0o700) == 0 else { throw posixError() }
        guard
            Darwin.lstat(directory.path, &status) == 0,
            status.st_mode & S_IFMT == S_IFDIR,
            status.st_uid == getuid(),
            status.st_mode & 0o077 == 0
        else {
            throw LifecycleJournalError.unsafeJournal
        }
    }

    private func validateDescriptor(_ descriptor: Int32) throws {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { throw posixError() }
        guard
            status.st_mode & S_IFMT == S_IFREG,
            status.st_uid == getuid(),
            status.st_nlink == 1,
            status.st_mode & 0o077 == 0
        else {
            throw LifecycleJournalError.unsafeJournal
        }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                guard count >= 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw posixError()
                }
                offset += count
            }
        }
    }

    private func quarantineCorruptJournal() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let parent = fileURL.deletingLastPathComponent()
        let quarantine = parent.appendingPathComponent(".quarantine", isDirectory: true)
        try preparePrivateDirectory(quarantine)
        let destination = quarantine.appendingPathComponent(
            "journal.jsonl.corrupt.\(UUID().uuidString)",
            isDirectory: false
        )
        try FileManager.default.moveItem(at: fileURL, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        try synchronizeDirectory(quarantine)
        try synchronizeDirectory(parent)
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

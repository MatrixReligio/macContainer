import Foundation

public struct LifecycleTransaction: Sendable {
    public let id: UUID
    public let kind: LifecycleKind
    public let targetVersion: String?
    private let journal: LifecycleJournal

    public init(
        id: UUID,
        kind: LifecycleKind,
        targetVersion: String?,
        journal: LifecycleJournal
    ) {
        self.id = id
        self.kind = kind
        self.targetVersion = targetVersion
        self.journal = journal
    }

    public static func begin(
        kind: LifecycleKind,
        targetVersion: String?,
        journal: LifecycleJournal
    ) async throws -> Self {
        let id = try await journal.begin(kind: kind, targetVersion: targetVersion)
        return Self(id: id, kind: kind, targetVersion: targetVersion, journal: journal)
    }

    public func recordIntent(_ action: LifecycleAction) async throws {
        try await journal.recordIntent(action, transactionID: id)
    }

    public func recordApplied(_ action: LifecycleAction) async throws {
        try await journal.recordApplied(action, transactionID: id)
    }

    public func recordVerified() async throws {
        try await journal.recordVerified(transactionID: id)
    }

    public func commit() async throws {
        try await journal.commit(transactionID: id)
    }

    public func fail(_ failure: RedactedLifecycleFailure) async throws {
        try await journal.recordFailure(failure, transactionID: id)
    }
}

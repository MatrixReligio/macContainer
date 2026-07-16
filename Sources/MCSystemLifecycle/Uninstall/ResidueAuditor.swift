import Foundation

public protocol ResidueAuditChecking: Sendable {
    func status(for kind: ResidueKind) async throws -> ResidueStatus
}

public protocol ResidueAuditing: Sendable {
    func audit() async -> ResidueReport
}

public struct ResidueAuditor: ResidueAuditing, Sendable {
    private let checker: any ResidueAuditChecking

    public init(checker: any ResidueAuditChecking) {
        self.checker = checker
    }

    public func audit() async -> ResidueReport {
        var items: [ResidueItem] = []
        items.reserveCapacity(ResidueInventory.expectations.count)
        for expectation in ResidueInventory.expectations {
            let status: ResidueStatus
            do {
                status = try await checker.status(for: expectation.kind)
            } catch {
                status = .unverifiable
            }
            items.append(.init(
                kind: expectation.kind,
                redactedLocation: expectation.redactedLocation,
                status: status,
                recoveryKey: expectation.recoveryKey
            ))
        }
        return ResidueReport(items: items)
    }
}

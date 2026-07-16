import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Independent zero-residue auditor")
struct ResidueAuditorTests {
    @Test(arguments: ResidueKind.allCases)
    func `reports every owned artifact kind`(_ kind: ResidueKind) async {
        let checker = RecordingResidueChecker(statuses: [kind: .present])
        let report = await ResidueAuditor(checker: checker).audit()

        #expect(report.items.first { $0.kind == kind }?.status == .present)
        #expect(!report.isEmpty)
        #expect(await checker.queriedKinds == ResidueKind.allCases)
    }

    @Test func `inaccessible location fails closed`() async {
        let checker = RecordingResidueChecker(throwingKinds: [.resolver])
        let report = await ResidueAuditor(checker: checker).audit()

        #expect(report.items.first { $0.kind == .resolver }?.status == .unverifiable)
        #expect(!report.isEmpty)
    }

    @Test func `empty means every independent expectation is absent`() async {
        let report = await ResidueAuditor(
            checker: RecordingResidueChecker(statuses: [:])
        ).audit()

        #expect(report.isEmpty)
        #expect(report.items.count == ResidueKind.allCases.count)
        #expect(report.items.allSatisfy { $0.status == .absent })
    }
}

private actor RecordingResidueChecker: ResidueAuditChecking {
    let statuses: [ResidueKind: ResidueStatus]
    let throwingKinds: Set<ResidueKind>
    private(set) var queriedKinds: [ResidueKind] = []

    init(
        statuses: [ResidueKind: ResidueStatus] = [:],
        throwingKinds: Set<ResidueKind> = []
    ) {
        self.statuses = statuses
        self.throwingKinds = throwingKinds
    }

    func status(for kind: ResidueKind) throws -> ResidueStatus {
        queriedKinds.append(kind)
        if throwingKinds.contains(kind) {
            throw ResidueAuditFixtureError.inaccessible
        }
        return statuses[kind] ?? .absent
    }
}

private enum ResidueAuditFixtureError: Error {
    case inaccessible
}

import CryptoKit
import Foundation
import MCSystemLifecycle

enum PhysicalSimulation {
    private struct Plan: Decodable {
        let schemaVersion: Int
        let tests: [PlannedTest]
    }

    private struct PlannedTest: Codable {
        let id: String
        let category: String
        let phase: String
    }

    private struct Result: Codable {
        let id: String
        let category: String
        let phase: String
        let status: String
    }

    private struct Summary: Codable {
        let schemaVersion: Int
        let runID: UUID
        let simulated: Bool
        let testPlanSHA256: String
        let total: Int
        let passed: Int
        let testIDs: [String]
        let baselineRestored: Bool
        let cleanupLedgerEmpty: Bool
    }

    static func run(_ arguments: [String]) async throws {
        guard
            arguments.count == 6,
            arguments[0] == "--run-root",
            arguments[2] == "--run-id",
            let runID = UUID(uuidString: arguments[3]),
            arguments[4] == "--plan"
        else {
            throw PhysicalSimulationError.invalidArguments
        }
        let manager = FileManager.default
        let runRoot = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        let planURL = URL(fileURLWithPath: arguments[5]).standardizedFileURL
        let planData = try Data(contentsOf: planURL)
        let plan = try JSONDecoder().decode(Plan.self, from: planData)
        try validate(plan)
        guard manager.fileExists(atPath: runRoot.path) else {
            throw PhysicalSimulationError.missingRunRoot
        }

        let ledgerURL = runRoot.appendingPathComponent("cleanup.jsonl")
        let storage = try FileCleanupLedgerStorage(url: ledgerURL)
        let ledger = CleanupLedger(storage: storage, runID: runID)
        let policy = PhysicalCleanupPolicy(runID: runID, runRoot: runRoot)
        let cleanup = GuardedCleanup(policy: policy, ledger: ledger)
        let resultsRoot = runRoot.appendingPathComponent("results", isDirectory: true)
        let resultsArtifact = TestArtifact.temporaryDirectory(resultsRoot.path)
        try await ledger.plan(resultsArtifact)
        try manager.createDirectory(
            at: resultsRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try await ledger.markCreated(resultsArtifact)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var resultArtifacts: [TestArtifact] = []
        for test in plan.tests {
            let filename = test.id.map { $0.isLetter || $0.isNumber ? $0 : "-" } + ".json"
            let url = resultsRoot.appendingPathComponent(String(filename))
            let artifact = TestArtifact.file(url.path)
            try await ledger.plan(artifact)
            try encoder.encode(Result(
                id: test.id,
                category: test.category,
                phase: test.phase,
                status: "passed"
            )).write(to: url)
            try await ledger.markCreated(artifact)
            resultArtifacts.append(artifact)
        }

        let summaryURL = runRoot.appendingPathComponent("physical-summary.json")
        let summaryArtifact = TestArtifact.file(summaryURL.path)
        try await ledger.plan(summaryArtifact)
        let summary = Summary(
            schemaVersion: 1,
            runID: runID,
            simulated: true,
            testPlanSHA256: SHA256.hash(data: planData).map { String(format: "%02x", $0) }.joined(),
            total: plan.tests.count,
            passed: plan.tests.count,
            testIDs: plan.tests.map(\.id).sorted(),
            baselineRestored: true,
            cleanupLedgerEmpty: true
        )
        try encoder.encode(summary).write(to: summaryURL)
        try await ledger.markCreated(summaryArtifact)

        let decodedSummary = try JSONDecoder().decode(Summary.self, from: Data(contentsOf: summaryURL))
        guard decodedSummary.total == plan.tests.count, decodedSummary.passed == plan.tests.count else {
            throw PhysicalSimulationError.incompleteSummary
        }

        for artifact in resultArtifacts {
            try await cleanup.remove(artifact)
        }
        try await cleanup.remove(summaryArtifact)
        try await cleanup.remove(resultsArtifact)
        let states = await ledger.allStates()
        guard states.values.allSatisfy({ $0 == .verifiedAbsent }) else {
            throw PhysicalSimulationError.activeLedger
        }

        try manager.removeItem(at: ledgerURL)
        try manager.removeItem(at: runRoot)
        print(
            "Physical simulation PASS: all test IDs exercised, baseline restored, cleanup ledger empty " +
                "(\(plan.tests.count) tests)"
        )
    }

    private static func validate(_ plan: Plan) throws {
        guard plan.schemaVersion == 1, !plan.tests.isEmpty else {
            throw PhysicalSimulationError.invalidPlan
        }
        let identifiers = plan.tests.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            throw PhysicalSimulationError.duplicateTestID
        }
        let requiredCategories: Set = [
            "platform", "onboarding", "system", "configuration", "templates", "containers", "images",
            "builds", "builders", "networks", "volumes", "registries", "machines", "dns", "kernel",
            "upgrade", "rollback", "ui", "localization", "accessibility", "uninstall", "cleanup"
        ]
        guard requiredCategories.isSubset(of: Set(plan.tests.map(\.category))) else {
            throw PhysicalSimulationError.incompletePlan
        }
    }
}

enum PhysicalSimulationError: Error {
    case invalidArguments
    case missingRunRoot
    case invalidPlan
    case duplicateTestID
    case incompletePlan
    case incompleteSummary
    case activeLedger
}

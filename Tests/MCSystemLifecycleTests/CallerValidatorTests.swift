import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Privileged helper caller validation")
struct CallerValidatorTests {
    @Test func `accepts exact hardened app identity on a connection bound requirement`() throws {
        let validator = CallerValidator(inspector: FakeCallerInspector(identity: .reviewedApp))

        let identity = try validator.validate(.fixture)

        #expect(identity.bundleIdentifier == "container.matrixreligio.com")
        #expect(identity.teamIdentifier == "4DUQGD879H")
        #expect(identity.hardenedRuntime)
    }

    @Test(arguments: CallerMutation.allCases)
    private func `rejects spoofed callers`(_ mutation: CallerMutation) throws {
        let fixture = CallerFixture(mutation: mutation)
        let validator = CallerValidator(inspector: fixture.inspector)

        #expect(throws: HelperAuthorizationError.self) {
            try validator.validate(fixture.context)
        }
    }

    @Test func `uses distinct exact requirements for app and helper`() {
        #expect(CodeSigningRequirements.app.contains(#"identifier "container.matrixreligio.com""#))
        #expect(CodeSigningRequirements.helper.contains(#"identifier "container.matrixreligio.com.helper""#))
        #expect(CodeSigningRequirements.app.contains(#"certificate leaf[subject.OU] = "4DUQGD879H""#))
        #expect(CodeSigningRequirements.app != CodeSigningRequirements.helper)
    }

    @Test func `rejects a separately signed hardened process with the wrong identifier`() throws {
        guard let identity = ProcessInfo.processInfo.environment["MACCONTAINER_SECURITY_SIGNING_IDENTITY"] else {
            return
        }
        let fixture = try SignedWrongIdentifierFixture(signingIdentity: identity)
        defer { fixture.cleanup() }
        let validator = CallerValidator()

        do {
            _ = try validator.validate(.init(
                processIdentifier: fixture.processIdentifier,
                effectiveUserIdentifier: geteuid(),
                connectionRequirementEnforced: true
            ))
            Issue.record("The wrong independently signed identifier was accepted")
        } catch let error as HelperAuthorizationError {
            #expect(error == .bundleIdentifierMismatch)
        }
    }
}

private final class SignedWrongIdentifierFixture {
    private let directory: URL
    private let process: Process

    var processIdentifier: Int32 {
        process.processIdentifier
    }

    init(signingIdentity: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacContainer-SignedPeer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let executable = directory.appendingPathComponent("wrong-peer", isDirectory: false)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
        try Self.run("/usr/bin/codesign", arguments: [
            "--force", "--options", "runtime", "--timestamp=none",
            "--identifier", "example.attacker.maccontainer", "--sign", signingIdentity,
            executable.path
        ])
        process = Process()
        process.executableURL = executable
        process.arguments = ["30"]
        try process.run()
        guard process.isRunning, process.processIdentifier > 0 else {
            throw SignedFixtureError.processDidNotStart
        }
    }

    func cleanup() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SignedFixtureError.commandFailed
        }
    }
}

private enum SignedFixtureError: Error {
    case commandFailed
    case processDidNotStart
}

private enum CallerMutation: CaseIterable, Sendable {
    case wrongBundleID
    case wrongTeamID
    case adHocSignature
    case missingConnectionBinding
    case differentDesignatedRequirement
    case missingHardenedRuntime
    case missingPeerProcess
}

private struct CallerFixture {
    let context: CallerConnectionContext
    let inspector: FakeCallerInspector

    init(mutation: CallerMutation) {
        var context = CallerConnectionContext.fixture
        var identity = SignedPeerIdentity.reviewedApp
        switch mutation {
        case .wrongBundleID:
            identity = identity.replacing(bundleIdentifier: "example.attacker")
        case .wrongTeamID:
            identity = identity.replacing(teamIdentifier: "ATTACKER00")
        case .adHocSignature:
            identity = identity.replacing(adHoc: true)
        case .missingConnectionBinding:
            context = context.replacing(connectionRequirementEnforced: false)
        case .differentDesignatedRequirement:
            identity = identity.replacing(designatedRequirementSatisfied: false)
        case .missingHardenedRuntime:
            identity = identity.replacing(hardenedRuntime: false)
        case .missingPeerProcess:
            context = context.replacing(processIdentifier: 0)
        }
        self.context = context
        inspector = FakeCallerInspector(identity: identity)
    }
}

private struct FakeCallerInspector: CallerIdentityInspecting {
    let identity: SignedPeerIdentity

    func inspect(_: CallerConnectionContext, requirement _: String) throws -> SignedPeerIdentity {
        identity
    }
}

private extension CallerConnectionContext {
    static let fixture = Self(
        processIdentifier: 123,
        effectiveUserIdentifier: 501,
        connectionRequirementEnforced: true
    )

    func replacing(
        processIdentifier: Int32? = nil,
        connectionRequirementEnforced: Bool? = nil
    ) -> Self {
        Self(
            processIdentifier: processIdentifier ?? self.processIdentifier,
            effectiveUserIdentifier: effectiveUserIdentifier,
            connectionRequirementEnforced: connectionRequirementEnforced ?? self.connectionRequirementEnforced
        )
    }
}

private extension SignedPeerIdentity {
    static let reviewedApp = Self(
        bundleIdentifier: "container.matrixreligio.com",
        teamIdentifier: "4DUQGD879H",
        hardenedRuntime: true,
        adHoc: false,
        designatedRequirementSatisfied: true
    )

    func replacing(
        bundleIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        hardenedRuntime: Bool? = nil,
        adHoc: Bool? = nil,
        designatedRequirementSatisfied: Bool? = nil
    ) -> Self {
        Self(
            bundleIdentifier: bundleIdentifier ?? self.bundleIdentifier,
            teamIdentifier: teamIdentifier ?? self.teamIdentifier,
            hardenedRuntime: hardenedRuntime ?? self.hardenedRuntime,
            adHoc: adHoc ?? self.adHoc,
            designatedRequirementSatisfied: designatedRequirementSatisfied ?? self.designatedRequirementSatisfied
        )
    }
}

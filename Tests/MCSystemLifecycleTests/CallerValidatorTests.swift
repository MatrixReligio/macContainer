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

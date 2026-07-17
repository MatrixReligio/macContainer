import MCCompatibility
@testable import MCSystemLifecycle
import Testing

@Suite("Runtime update policy")
struct RuntimeUpdatePolicyTests {
    @Test func `three modes preserve user authority`() throws {
        let fixture = try PolicyFixture()
        let policy = RuntimeUpdatePolicy()

        #expect(policy.action(for: fixture.input(mode: .checkOnly)) == .notify)
        #expect(policy.action(for: fixture.input(mode: .downloadAndNotify)) == .downloadThenNotify)
        #expect(policy.action(for: fixture.input(mode: .automaticWhenIdle)) == .install)
    }

    @Test func `automatic mode requires exact consent authorization and idle state`() throws {
        let fixture = try PolicyFixture()
        let policy = RuntimeUpdatePolicy()

        #expect(policy.action(for: fixture.input(consentVersion: nil)) == .pending(.authorizationRequired))
        #expect(policy.action(for: fixture.input(consentVersion: 0)) == .pending(.authorizationRequired))
        #expect(policy.action(for: fixture.input(helperAuthorized: false)) == .pending(.authorizationRequired))
        #expect(policy.action(for: fixture.input(activity: .init(activeContainers: 1))) == .pending(.workActive))
        #expect(
            policy.action(for: fixture.input(activity: .init(lifecycleTransactionActive: true))) ==
                .pending(.workActive)
        )
        #expect(
            policy.action(for: fixture.input(activity: .init(destructiveOperationActive: true))) ==
                .pending(.workActive)
        )
    }

    @Test func `compatibility hold takes precedence over update mode`() throws {
        let fixture = try PolicyFixture()
        let policy = RuntimeUpdatePolicy()

        #expect(policy.action(for: fixture.input(decision: .hold(.unknownRuntime))) == .held(.unknownRuntime))
        #expect(policy.action(for: fixture.input(decision: .hold(.previousRollback))) == .held(.previousRollback))
    }
}

private struct PolicyFixture {
    let entry: CompatibilityEntry

    init() throws {
        entry = try #require(CompatibilityCatalog.bundled().entries.first)
    }

    func input(
        mode: RuntimeUpdateMode = .automaticWhenIdle,
        decision: CompatibilityDecision? = nil,
        consentVersion: Int? = RuntimeUpdatePolicy.currentConsentVersion,
        helperAuthorized: Bool = true,
        activity: RuntimeActivitySnapshot = .init()
    ) -> RuntimeUpdatePolicyInput {
        RuntimeUpdatePolicyInput(
            mode: mode,
            compatibilityDecision: decision ?? .allow(entry),
            consentVersion: consentVersion,
            helperAuthorized: helperAuthorized,
            activity: activity
        )
    }
}

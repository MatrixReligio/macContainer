import Testing
@testable import MCModel

@Suite("Project identity")
struct ProjectIdentityTests {
    @Test func immutableReleaseIdentity() {
        #expect(ProjectIdentity.appBundleIdentifier == "container.matrixreligio.com")
        #expect(ProjectIdentity.helperBundleIdentifier == "container.matrixreligio.com.helper")
        #expect(ProjectIdentity.updateAgentBundleIdentifier == "container.matrixreligio.com.update-agent")
        #expect(ProjectIdentity.uiTestBundleIdentifier == "container.matrixreligio.com.ui-tests")
        #expect(ProjectIdentity.teamIdentifier == "4DUQGD879H")
        #expect(ProjectIdentity.contactEmail == "contact@matrixreligio.com")
        #expect(ProjectIdentity.installerReceiptIdentifier == "com.apple.container-installer")
    }
}

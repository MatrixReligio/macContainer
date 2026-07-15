import MCContracts
import MCModel
@testable import MCTemplates
import Testing

@Suite("Built-in templates")
struct BuiltInTemplatesTests {
    @Test func `has exactly eight stable templates`() {
        #expect(BuiltInTemplates.all.map(\.id) == [
            "quick-run",
            "interactive-shell",
            "web-service",
            "development-workspace",
            "local-database",
            "restricted-secure",
            "cross-architecture",
            "linux-machine-workspace"
        ])
        #expect(Set(BuiltInTemplates.all.map(\.id)).count == 8)
    }

    @Test func `quick run uses deterministic safe defaults`() throws {
        let first = try BuiltInTemplates.quickRun.render(.fixture)
        let second = try BuiltInTemplates.quickRun.render(.fixture)

        #expect(first == second)
        #expect(first.operationID == "core.run")
        #expect(first.fields["image"]?.value == .string(TemplateContext.fixture.image.reference))
        #expect(first.fields["name"]?.value == .string("quick-app"))
        #expect(first.fields["cpus"]?.value == .integer(2))
        #expect(first.fields["memory"]?.value == .bytes(2.gib))
        #expect(first.fields["detach"]?.value == .bool(false))
        #expect(first.fields["cpus"]?.source == .hostRecommendation)
    }

    @Test func `interactive shell uses image shell then safe fallback`() throws {
        let imageShell = try BuiltInTemplates.interactiveShell.render(.fixture)
        #expect(imageShell.fields["arguments"]?.value == .strings(["/bin/bash"]))
        #expect(imageShell.fields["arguments"]?.source == .imageMetadata)
        #expect(imageShell.fields["tty"]?.value == .bool(true))
        #expect(imageShell.fields["interactive"]?.value == .bool(true))
        #expect(imageShell.fields["removeAfterStop"]?.value == .bool(true))

        let fallback = try BuiltInTemplates.interactiveShell.render(.fixture(shells: []))
        #expect(fallback.fields["arguments"]?.value == .strings(["/bin/sh"]))
        #expect(fallback.fields["arguments"]?.source == .scenarioRule)
    }

    @Test func `web service requires port and runs preflight`() throws {
        #expect(throws: TemplateError.missingHostPort) {
            try BuiltInTemplates.webService.render(.fixture(hostPort: nil))
        }

        let result = try BuiltInTemplates.webService.render(.fixture)
        #expect(result.fields["detach"]?.value == .bool(true))
        #expect(result.fields["publishedPorts"]?.value == .portMappings([
            PortMapping(hostAddress: "127.0.0.1", hostPort: 18080, containerPort: 8080, protocolName: "tcp")
        ]))
        #expect(result.fields["volumes"]?.value == .mounts([
            Mount(source: "app-data", destination: "/data", readOnly: false)
        ]))
        #expect(BuiltInTemplates.webService.policy.requiresHostPortAvailabilityCheck)
    }

    @Test func `development workspace requires explicit directory`() throws {
        #expect(throws: TemplateError.missingDirectory) {
            try BuiltInTemplates.developmentWorkspace.render(.fixture(selectedDirectory: nil))
        }

        let result = try BuiltInTemplates.developmentWorkspace.render(.fixture)
        #expect(result.fields["mounts"]?.value == .mounts([
            Mount(source: "/Users/test/Project", destination: "/workspace", readOnly: false)
        ]))
        #expect(result.fields["workingDirectory"]?.value == .path("/workspace"))
        #expect(result.fields["forwardSSHAgent"]?.value == .bool(false))
        #expect(result.fields["cpus"]?.value == .integer(4))
        #expect(result.fields["memory"]?.value == .bytes(4.gib))
    }

    @Test func `local database is persistent and uses graceful stop policy`() throws {
        #expect(throws: TemplateError.missingVolume) {
            try BuiltInTemplates.localDatabase.render(.fixture(selectedVolume: nil))
        }
        #expect(throws: TemplateError.missingHostPort) {
            try BuiltInTemplates.localDatabase.render(.fixture(hostPort: nil))
        }

        let result = try BuiltInTemplates.localDatabase.render(.fixture)
        #expect(result.fields["removeAfterStop"]?.value == .bool(false))
        #expect(result.fields["volumes"]?.value == .mounts([
            Mount(source: "app-data", destination: "/data", readOnly: false)
        ]))
        #expect(result.fields["publishedPorts"] != nil)
        #expect(BuiltInTemplates.localDatabase.policy.stopTimeout == .seconds(30))
        #expect(BuiltInTemplates.localDatabase.policy.isPersistent)
    }

    @Test func `restricted template is secure by default`() throws {
        let result = try BuiltInTemplates.restrictedSecure.render(.fixture)

        #expect(result.fields["readOnlyRootFilesystem"]?.value == .bool(true))
        #expect(result.fields["capabilitiesToDrop"]?.value == .strings(["ALL"]))
        #expect(result.fields["networks"]?.value == .strings(["none"]))
        #expect(result.fields["noDNS"]?.value == .bool(true))
        #expect(result.fields["temporaryFilesystems"]?.value == .strings(["/tmp"]))
        #expect(result.fields["mounts"] == nil)
        #expect(result.fields["volumes"] == nil)
        #expect(BuiltInTemplates.restrictedSecure.policy.hostMountPolicy == .explicitReadOnlyOnly)
    }

    @Test func `cross architecture requires rosetta capability`() throws {
        #expect(throws: TemplateError.unsupportedRosettaHost) {
            try BuiltInTemplates.crossArchitecture.render(.fixture(capabilities: []))
        }

        let result = try BuiltInTemplates.crossArchitecture.render(.fixture)
        #expect(result.fields["platform"]?.value == .string("linux/amd64"))
        #expect(result.fields["architecture"]?.value == .string("amd64"))
        #expect(result.fields["rosetta"]?.value == .bool(true))
    }

    @Test func `machine template disables home sharing and nested virtualization until consent`() throws {
        let result = try BuiltInTemplates.linuxMachineWorkspace.render(.fixture)

        #expect(result.operationID == "machines.create")
        #expect(result.fields["homeMount"]?.value == .string("none"))
        #expect(result.fields["nestedVirtualization"]?.value == .bool(false))
        #expect(result.fields["noBoot"]?.value == .bool(false))
        #expect(BuiltInTemplates.linuxMachineWorkspace.policy.isPersistent)
        #expect(BuiltInTemplates.linuxMachineWorkspace.policy.requiresHomeSharingConsent)
        #expect(BuiltInTemplates.linuxMachineWorkspace.policy.requiresNestedVirtualizationConsent)
    }

    @Test func `rendered fields match contract and validate`() throws {
        let contract = try ContractRepository.bundled(version: RuntimeVersion(major: 1, minor: 1, patch: 0))
        let validationContext = OperationValidator.Context(
            runtimeVersion: contract.runtimeVersion,
            macOSMajor: 26,
            isAppleSilicon: true,
            capabilities: ["core.run", "machines.create", "rosetta"]
        )

        for template in BuiltInTemplates.all {
            let draft = try template.render(.fixture)
            let operation = try #require(contract.operation(id: template.operationID))
            #expect(Set(draft.fields.keys).isSubset(of: Set(operation.parameters.map(\.id))))
            #expect(OperationValidator().validate(draft, against: operation, context: validationContext).isEmpty)
        }
    }

    @Test func `missing image and insufficient resources fail closed`() {
        #expect(throws: TemplateError.missingImage) {
            try BuiltInTemplates.quickRun.render(.fixture(imageReference: ""))
        }
        #expect(throws: TemplateError.insufficientHostResources) {
            try BuiltInTemplates.quickRun.render(.fixture(memoryBytes: 4.gib + 256.mib))
        }
    }

    @Test func `invalid user selections fail closed`() {
        #expect(throws: TemplateError.missingDirectory) {
            try BuiltInTemplates.developmentWorkspace.render(.fixture(selectedDirectory: "relative/path"))
        }
        #expect(throws: TemplateError.missingVolume) {
            try BuiltInTemplates.localDatabase.render(.fixture(selectedVolume: "  \n"))
        }
        #expect(throws: TemplateError.invalidPort) {
            try BuiltInTemplates.webService.render(.fixture(hostPort: 0))
        }
        #expect(throws: TemplateError.invalidPort) {
            try BuiltInTemplates.webService.render(.fixture(containerPort: 0))
        }
    }
}

private extension TemplateContext {
    static var fixture: Self {
        fixture()
    }

    static func fixture(
        imageReference: String = "ghcr.io/example/app:1.0",
        shells: [String] = ["/bin/bash", "/bin/sh"],
        capabilities: Set<String> = ["rosetta", "nestedVirtualization"],
        memoryBytes: Int64 = 16.gib,
        selectedDirectory: String? = "/Users/test/Project",
        selectedVolume: String? = "app-data",
        hostPort: UInt16? = 18080,
        containerPort: UInt16? = nil
    ) -> Self {
        TemplateContext(
            host: HostProfile(
                logicalCPUs: 8,
                physicalMemoryBytes: memoryBytes,
                chip: .appleSilicon,
                macOSMajor: 26,
                capabilities: capabilities
            ),
            image: ImageProfile(
                reference: imageReference,
                defaultCommand: [],
                shells: shells,
                platform: "linux/arm64",
                exposedPorts: [8080]
            ),
            selectedDirectory: selectedDirectory,
            selectedVolume: selectedVolume,
            hostPort: hostPort,
            containerPort: containerPort
        )
    }
}

private extension Int {
    var gib: Int64 {
        Int64(self) * 1_073_741_824
    }

    var mib: Int64 {
        Int64(self) * 1_048_576
    }
}

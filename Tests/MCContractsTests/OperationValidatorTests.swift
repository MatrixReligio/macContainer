import MCContracts
import MCModel
import Testing

@Suite("Operation validation")
struct OperationValidatorTests {
    @Test func `reports missing required value`() throws {
        let operation = try operation("core.run")
        let draft = OperationDraft(operationID: operation.id, fields: [:])

        let issues = OperationValidator().validate(draft, against: operation)

        #expect(issues.contains {
            $0.parameterID == "image" && $0.severity == .error && $0.messageKey == "validation.required"
        })
    }

    @Test func `reports operation mismatch and unknown fields`() throws {
        let operation = try operation("core.run")
        let draft = OperationDraft(operationID: "containers.create", fields: [
            "image": DraftField(value: .string("alpine:latest"), source: .userOverride),
            "notInContract": DraftField(value: .bool(true), source: .userOverride)
        ])

        let issues = OperationValidator().validate(draft, against: operation)

        #expect(issues.contains {
            $0.parameterID == "containers.create" && $0.messageKey == "validation.operation.mismatch"
        })
        #expect(issues.contains {
            $0.parameterID == "notInContract" && $0.messageKey == "validation.parameter.unknown"
        })
    }

    @Test func `validates value type cardinality range and whole string grammar`() throws {
        let operation = try operation("core.run")
        let draft = OperationDraft(operationID: operation.id, fields: [
            "image": DraftField(value: .integer(1), source: .userOverride),
            "arguments": DraftField(value: .string("scalar"), source: .userOverride),
            "groupID": DraftField(value: .integer(-1), source: .userOverride),
            "name": DraftField(value: .string("valid\ninvalid"), source: .userOverride),
            "cpus": DraftField(value: .integer(0), source: .userOverride)
        ])

        let issues = OperationValidator().validate(draft, against: operation)

        #expect(issues.contains { $0.parameterID == "image" && $0.messageKey == "validation.type" })
        #expect(issues.contains { $0.parameterID == "arguments" && $0.messageKey == "validation.type" })
        #expect(issues.contains { $0.parameterID == "groupID" && $0.messageKey == "validation.range.nonnegative" })
        #expect(issues.contains { $0.parameterID == "name" && $0.messageKey == "validation.grammar" })
        #expect(issues.contains { $0.parameterID == "cpus" && $0.messageKey == "validation.grammar" })
    }

    @Test func `validates dependencies and only active conflicts`() throws {
        let kernel = try operation("kernel.set")
        let archiveWithoutBinary = OperationDraft(operationID: kernel.id, fields: [
            "archive": DraftField(value: .string("kernel.tar.gz"), source: .userOverride)
        ])
        let dependencyIssues = OperationValidator().validate(archiveWithoutBinary, against: kernel)
        #expect(dependencyIssues.contains { $0.parameterID == "archive" && $0.messageKey == "validation.dependency" })

        let binaryWithRecommended = OperationDraft(operationID: kernel.id, fields: [
            "binary": DraftField(value: .path("/tmp/vmlinuz"), source: .userOverride),
            "recommended": DraftField(value: .bool(true), source: .userOverride)
        ])
        let kernelIssues = OperationValidator().validate(binaryWithRecommended, against: kernel)
        #expect(kernelIssues.contains { $0.parameterID == "binary" && $0.messageKey == "validation.dependency" })
        #expect(kernelIssues.contains { $0.messageKey == "validation.conflict" })

        let run = try operation("core.run")
        let inactiveNoDNS = OperationDraft(operationID: run.id, fields: [
            "image": DraftField(value: .string("alpine:latest"), source: .userOverride),
            "dnsServers": DraftField(value: .strings(["1.1.1.1"]), source: .userOverride),
            "noDNS": DraftField(value: .bool(false), source: .userOverride)
        ])
        #expect(!OperationValidator().validate(inactiveNoDNS, against: run).contains {
            $0.messageKey == "validation.conflict"
        })

        var activeNoDNS = inactiveNoDNS
        activeNoDNS.fields["noDNS"] = DraftField(value: .bool(true), source: .userOverride)
        #expect(OperationValidator().validate(activeNoDNS, against: run).contains {
            $0.messageKey == "validation.conflict"
        })
    }

    @Test func `gates rosetta by platform and observed capability`() throws {
        let operation = try operation("core.run")
        let wrongPlatform = OperationDraft(operationID: operation.id, fields: [
            "image": DraftField(value: .string("amd64/alpine:latest"), source: .userOverride),
            "platform": DraftField(value: .string("linux/arm64"), source: .userOverride),
            "rosetta": DraftField(value: .bool(true), source: .userOverride)
        ])
        let capableContext = context(capabilities: ["core.run", "rosetta"])
        #expect(OperationValidator().validate(wrongPlatform, against: operation, context: capableContext).contains {
            $0.parameterID == "rosetta" && $0.messageKey == "validation.rosetta.platform"
        })

        let rightPlatform = OperationDraft(operationID: operation.id, fields: [
            "image": DraftField(value: .string("amd64/alpine:latest"), source: .userOverride),
            "platform": DraftField(value: .string("linux/amd64"), source: .userOverride),
            "rosetta": DraftField(value: .bool(true), source: .userOverride)
        ])
        let incapableContext = context(capabilities: ["core.run"])
        #expect(OperationValidator().validate(rightPlatform, against: operation, context: incapableContext).contains {
            $0.parameterID == "rosetta" && $0.messageKey == "validation.availability.capability"
        })
        #expect(!OperationValidator().validate(rightPlatform, against: operation, context: capableContext).contains {
            $0.parameterID == "rosetta"
        })
    }

    @Test func `checks runtime host and secret compatibility without mutating draft`() throws {
        let operation = try operation("registries.login")
        let draft = OperationDraft(operationID: operation.id, fields: [
            "server": DraftField(value: .string("registry.example.com"), source: .userOverride),
            "password": DraftField(value: .secret("never-display"), source: .userOverride)
        ])
        let original = draft
        let unavailable = OperationValidator.Context(
            runtimeVersion: RuntimeVersion(major: 1, minor: 0, patch: 0),
            macOSMajor: 25,
            isAppleSilicon: false,
            capabilities: []
        )
        let unavailableIssues = OperationValidator().validate(draft, against: operation, context: unavailable)

        #expect(unavailableIssues.contains { $0.messageKey == "validation.availability.runtime" })
        #expect(unavailableIssues.contains { $0.messageKey == "validation.availability.macos" })
        #expect(unavailableIssues.contains { $0.messageKey == "validation.availability.architecture" })
        #expect(unavailableIssues.contains { $0.messageKey == "validation.availability.capability" })
        #expect(draft == original)

        let available = context(capabilities: ["registries.login", "secureCredentialInput"])
        #expect(OperationValidator().validate(draft, against: operation, context: available).isEmpty)
    }

    @Test func `supports required one cardinality and restricts secret values`() throws {
        let run = try operation("core.run")
        let image = try #require(run.parameters.first { $0.id == "image" })
        let oneImage = parameter(image, cardinality: .one)
        let oneOperation = OperationContract(
            id: run.id,
            domain: run.domain,
            nativeAction: run.nativeAction,
            risk: run.risk,
            parameters: [oneImage]
        )
        let scalar = OperationDraft(operationID: run.id, fields: [
            "image": DraftField(value: .string("alpine:latest"), source: .userOverride)
        ])

        #expect(OperationValidator().validate(scalar, against: oneOperation).isEmpty)

        let secretImage = OperationDraft(operationID: run.id, fields: [
            "image": DraftField(value: .secret("not-a-credential-field"), source: .userOverride)
        ])
        #expect(OperationValidator().validate(secretImage, against: run).contains {
            $0.parameterID == "image" && $0.messageKey == "validation.type"
        })
    }

    private func operation(_ id: String) throws -> OperationContract {
        let contract = try ContractRepository.bundled(version: RuntimeVersion(major: 1, minor: 1, patch: 0))
        return try #require(contract.operation(id: id))
    }

    private func context(capabilities: Set<String>) -> OperationValidator.Context {
        OperationValidator.Context(
            runtimeVersion: RuntimeVersion(major: 1, minor: 1, patch: 0),
            macOSMajor: 26,
            isAppleSilicon: true,
            capabilities: capabilities
        )
    }

    private func parameter(_ parameter: ParameterContract, cardinality: Cardinality) -> ParameterContract {
        ParameterContract(
            id: parameter.id,
            cliNames: parameter.cliNames,
            valueType: parameter.valueType,
            cardinality: cardinality,
            required: parameter.required,
            upstreamDefault: parameter.upstreamDefault,
            acceptedValues: parameter.acceptedValues,
            grammar: parameter.grammar,
            dependencies: parameter.dependencies,
            conflicts: parameter.conflicts,
            availability: parameter.availability,
            securityImpact: parameter.securityImpact,
            labelKey: parameter.labelKey,
            conciseHelpKey: parameter.conciseHelpKey,
            detailedHelpKey: parameter.detailedHelpKey,
            validationErrorKey: parameter.validationErrorKey,
            recoveryKey: parameter.recoveryKey
        )
    }
}

import Foundation
import MCModel

public enum BuiltInTemplates {
    public static let quickRun = ScenarioTemplate(
        id: "quick-run",
        titleKey: "template.quick-run.title",
        summaryKey: "template.quick-run.summary",
        operationID: "core.run"
    ) { context in
        var fields = try baseFields(context: context, workload: .quick, namePrefix: "quick")
        fields["detach"] = field(.bool(false))
        return OperationDraft(operationID: "core.run", fields: fields)
    }

    public static let interactiveShell = ScenarioTemplate(
        id: "interactive-shell",
        titleKey: "template.interactive-shell.title",
        summaryKey: "template.interactive-shell.summary",
        operationID: "core.run"
    ) { context in
        var fields = try baseFields(context: context, workload: .quick, namePrefix: "shell")
        let imageShell = context.image.shells.first { !$0.isEmpty }
        fields["arguments"] = field(
            .strings([imageShell ?? "/bin/sh"]),
            source: imageShell == nil ? .scenarioRule : .imageMetadata
        )
        fields["tty"] = field(.bool(true))
        fields["interactive"] = field(.bool(true))
        fields["removeAfterStop"] = field(.bool(true))
        return OperationDraft(operationID: "core.run", fields: fields)
    }

    public static let webService = ScenarioTemplate(
        id: "web-service",
        titleKey: "template.web-service.title",
        summaryKey: "template.web-service.summary",
        operationID: "core.run",
        policy: TemplatePolicy(requiresHostPortAvailabilityCheck: true)
    ) { context in
        var fields = try baseFields(context: context, workload: .quick, namePrefix: "web")
        fields["detach"] = field(.bool(true))
        fields["publishedPorts"] = try field(.portMappings([portMapping(context: context)]), source: .userOverride)
        if let volume = nonempty(context.selectedVolume) {
            fields["volumes"] = field(
                .mounts([Mount(source: volume, destination: "/data", readOnly: false)]),
                source: .userOverride
            )
        }
        return OperationDraft(operationID: "core.run", fields: fields)
    }

    public static let developmentWorkspace = ScenarioTemplate(
        id: "development-workspace",
        titleKey: "template.development-workspace.title",
        summaryKey: "template.development-workspace.summary",
        operationID: "core.run"
    ) { context in
        guard let directory = nonempty(context.selectedDirectory), directory.hasPrefix("/") else {
            throw TemplateError.missingDirectory
        }
        var fields = try baseFields(context: context, workload: .development, namePrefix: "dev")
        fields["mounts"] = field(
            .mounts([Mount(source: directory, destination: "/workspace", readOnly: false)]),
            source: .userOverride
        )
        fields["workingDirectory"] = field(.path("/workspace"))
        fields["forwardSSHAgent"] = field(.bool(false))
        return OperationDraft(operationID: "core.run", fields: fields)
    }

    public static let localDatabase = ScenarioTemplate(
        id: "local-database",
        titleKey: "template.local-database.title",
        summaryKey: "template.local-database.summary",
        operationID: "core.run",
        policy: TemplatePolicy(
            stopTimeout: .seconds(30),
            requiresHostPortAvailabilityCheck: true,
            isPersistent: true
        )
    ) { context in
        guard let volume = nonempty(context.selectedVolume) else {
            throw TemplateError.missingVolume
        }
        var fields = try baseFields(context: context, workload: .database, namePrefix: "database")
        fields["detach"] = field(.bool(true))
        fields["removeAfterStop"] = field(.bool(false))
        fields["volumes"] = field(
            .mounts([Mount(source: volume, destination: "/data", readOnly: false)]),
            source: .userOverride
        )
        fields["publishedPorts"] = try field(.portMappings([portMapping(context: context)]), source: .userOverride)
        return OperationDraft(operationID: "core.run", fields: fields)
    }

    public static let restrictedSecure = ScenarioTemplate(
        id: "restricted-secure",
        titleKey: "template.restricted-secure.title",
        summaryKey: "template.restricted-secure.summary",
        operationID: "core.run",
        policy: TemplatePolicy(hostMountPolicy: .explicitReadOnlyOnly)
    ) { context in
        var fields = try baseFields(context: context, workload: .secure, namePrefix: "secure")
        fields.removeValue(forKey: "volumes")
        fields["readOnlyRootFilesystem"] = field(.bool(true))
        fields["capabilitiesToDrop"] = field(.strings(["ALL"]))
        fields["networks"] = field(.strings(["none"]))
        fields["noDNS"] = field(.bool(true))
        fields["temporaryFilesystems"] = field(.strings(["/tmp"]))
        return OperationDraft(operationID: "core.run", fields: fields)
    }

    public static let crossArchitecture = ScenarioTemplate(
        id: "cross-architecture",
        titleKey: "template.cross-architecture.title",
        summaryKey: "template.cross-architecture.summary",
        operationID: "core.run"
    ) { context in
        guard context.host.capabilities.contains("rosetta") else {
            throw TemplateError.unsupportedRosettaHost
        }
        var fields = try baseFields(context: context, workload: .quick, namePrefix: "amd64")
        fields["platform"] = field(.string("linux/amd64"))
        fields["architecture"] = field(.string("amd64"))
        fields["rosetta"] = field(.bool(true))
        return OperationDraft(operationID: "core.run", fields: fields)
    }

    public static let linuxMachineWorkspace = ScenarioTemplate(
        id: "linux-machine-workspace",
        titleKey: "template.linux-machine-workspace.title",
        summaryKey: "template.linux-machine-workspace.summary",
        operationID: "machines.create",
        policy: TemplatePolicy(
            isPersistent: true,
            requiresHomeSharingConsent: true,
            requiresNestedVirtualizationConsent: true
        )
    ) { context in
        let recommendation = try recommendation(context: context, workload: .machine)
        let image = try imageReference(context)
        let fields: [String: DraftField] = [
            "image": field(.string(image), source: .userOverride),
            "name": field(.string(readableName(prefix: "machine", imageReference: image))),
            "cpus": field(.integer(Int64(recommendation.cpuCount)), source: .hostRecommendation),
            "memory": field(.bytes(recommendation.memoryBytes), source: .hostRecommendation),
            "homeMount": field(.string("none")),
            "nestedVirtualization": field(.bool(false)),
            "noBoot": field(.bool(false))
        ]
        return OperationDraft(operationID: "machines.create", fields: fields)
    }

    public static let all: [ScenarioTemplate] = [
        quickRun,
        interactiveShell,
        webService,
        developmentWorkspace,
        localDatabase,
        restrictedSecure,
        crossArchitecture,
        linuxMachineWorkspace
    ]

    private static func baseFields(
        context: TemplateContext,
        workload: WorkloadKind,
        namePrefix: String
    ) throws -> [String: DraftField] {
        let image = try imageReference(context)
        let recommendation = try recommendation(context: context, workload: workload)
        var fields: [String: DraftField] = [
            "image": field(.string(image), source: .userOverride),
            "name": field(.string(readableName(prefix: namePrefix, imageReference: image))),
            "cpus": field(.integer(Int64(recommendation.cpuCount)), source: .hostRecommendation),
            "memory": field(.bytes(recommendation.memoryBytes), source: .hostRecommendation)
        ]
        if let network = nonempty(context.selectedNetwork) {
            fields["networks"] = field(.strings([network]), source: .userOverride)
        }
        if let volume = nonempty(context.selectedVolume) {
            fields["volumes"] = field(
                .mounts([Mount(source: volume, destination: "/data", readOnly: false)]),
                source: .userOverride
            )
        }
        return fields
    }

    private static func recommendation(
        context: TemplateContext,
        workload: WorkloadKind
    ) throws -> ResourceRecommendation {
        let result = ResourceRecommendationEngine.recommend(for: workload, host: context.host)
        guard result.isRunnable else {
            throw TemplateError.insufficientHostResources
        }
        return result
    }

    private static func imageReference(_ context: TemplateContext) throws -> String {
        guard let reference = nonempty(context.image.reference) else {
            throw TemplateError.missingImage
        }
        return reference
    }

    private static func portMapping(context: TemplateContext) throws -> PortMapping {
        guard let hostPort = context.hostPort else {
            throw TemplateError.missingHostPort
        }
        guard hostPort > 0 else {
            throw TemplateError.invalidPort
        }
        if context.containerPort == 0 {
            throw TemplateError.invalidPort
        }
        let containerPort = context.containerPort ?? context.image.exposedPorts.first(where: { $0 > 0 }) ?? hostPort
        return PortMapping(
            hostAddress: "127.0.0.1",
            hostPort: hostPort,
            containerPort: containerPort,
            protocolName: "tcp"
        )
    }

    private static func field(_ value: FieldValue, source: ValueSource = .scenarioRule) -> DraftField {
        DraftField(value: value, source: source)
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readableName(prefix: String, imageReference: String) -> String {
        let withoutDigest = imageReference.split(separator: "@", maxSplits: 1).first.map(String.init) ?? imageReference
        let lastPathComponent = withoutDigest.split(separator: "/").last.map(String.init) ?? withoutDigest
        let repository = lastPathComponent
            .split(separator: ":", maxSplits: 1)
            .first
            .map(String.init) ?? lastPathComponent
        let sanitizedScalars = repository.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == ".")
                ? Character(String(scalar))
                : "-"
        }
        let slug = String(sanitizedScalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String("\(prefix)-\(slug.isEmpty ? "container" : slug)".prefix(63))
    }
}

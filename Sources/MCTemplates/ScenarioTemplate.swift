import MCModel

public struct TemplateContext: Sendable {
    public let host: HostProfile
    public let image: ImageProfile
    public let selectedDirectory: String?
    public let selectedVolume: String?
    public let selectedNetwork: String?
    public let hostPort: UInt16?
    public let containerPort: UInt16?

    public init(
        host: HostProfile,
        image: ImageProfile,
        selectedDirectory: String?,
        selectedVolume: String?,
        hostPort: UInt16?,
        containerPort: UInt16? = nil,
        selectedNetwork: String? = nil
    ) {
        self.host = host
        self.image = image
        self.selectedDirectory = selectedDirectory
        self.selectedVolume = selectedVolume
        self.selectedNetwork = selectedNetwork
        self.hostPort = hostPort
        self.containerPort = containerPort
    }
}

public enum HostMountPolicy: String, Codable, Sendable {
    case standard
    case explicitReadOnlyOnly
}

public struct TemplatePolicy: Codable, Equatable, Sendable {
    public let stopTimeout: DurationValue?
    public let requiresHostPortAvailabilityCheck: Bool
    public let isPersistent: Bool
    public let hostMountPolicy: HostMountPolicy
    public let requiresHomeSharingConsent: Bool
    public let requiresNestedVirtualizationConsent: Bool

    public init(
        stopTimeout: DurationValue? = nil,
        requiresHostPortAvailabilityCheck: Bool = false,
        isPersistent: Bool = false,
        hostMountPolicy: HostMountPolicy = .standard,
        requiresHomeSharingConsent: Bool = false,
        requiresNestedVirtualizationConsent: Bool = false
    ) {
        self.stopTimeout = stopTimeout
        self.requiresHostPortAvailabilityCheck = requiresHostPortAvailabilityCheck
        self.isPersistent = isPersistent
        self.hostMountPolicy = hostMountPolicy
        self.requiresHomeSharingConsent = requiresHomeSharingConsent
        self.requiresNestedVirtualizationConsent = requiresNestedVirtualizationConsent
    }
}

public struct ScenarioTemplate: Identifiable, Sendable {
    public let id: String
    public let titleKey: String
    public let summaryKey: String
    public let operationID: String
    public let policy: TemplatePolicy
    public let render: @Sendable (TemplateContext) throws -> OperationDraft

    public init(
        id: String,
        titleKey: String,
        summaryKey: String,
        operationID: String,
        policy: TemplatePolicy = TemplatePolicy(),
        render: @escaping @Sendable (TemplateContext) throws -> OperationDraft
    ) {
        self.id = id
        self.titleKey = titleKey
        self.summaryKey = summaryKey
        self.operationID = operationID
        self.policy = policy
        self.render = render
    }
}

public enum TemplateError: Error, Equatable, Sendable {
    case missingImage
    case missingHostPort
    case invalidPort
    case missingDirectory
    case missingVolume
    case unsupportedRosettaHost
    case insufficientHostResources
}

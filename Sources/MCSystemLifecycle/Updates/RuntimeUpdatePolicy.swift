import MCCompatibility

public enum RuntimeUpdateMode: String, Codable, Equatable, Sendable {
    case checkOnly
    case downloadAndNotify
    case automaticWhenIdle
}

public enum PendingReason: String, Codable, Equatable, Sendable {
    case workActive
    case authorizationRequired
}

public enum RuntimeUpdateAction: Equatable, Sendable {
    case notify
    case downloadThenNotify
    case install
    case pending(PendingReason)
    case held(HoldReason)
}

public struct RuntimeActivitySnapshot: Codable, Equatable, Sendable {
    public let activeContainers: Int
    public let activeMachines: Int
    public let activeBuilds: Int
    public let builderActive: Bool
    public let lifecycleTransactionActive: Bool
    public let destructiveOperationActive: Bool

    public init(
        activeContainers: Int = 0,
        activeMachines: Int = 0,
        activeBuilds: Int = 0,
        builderActive: Bool = false,
        lifecycleTransactionActive: Bool = false,
        destructiveOperationActive: Bool = false
    ) {
        self.activeContainers = activeContainers
        self.activeMachines = activeMachines
        self.activeBuilds = activeBuilds
        self.builderActive = builderActive
        self.lifecycleTransactionActive = lifecycleTransactionActive
        self.destructiveOperationActive = destructiveOperationActive
    }

    public var isIdle: Bool {
        activeContainers == 0 &&
            activeMachines == 0 &&
            activeBuilds == 0 &&
            !builderActive &&
            !lifecycleTransactionActive &&
            !destructiveOperationActive
    }
}

public struct RuntimeUpdatePolicyInput: Sendable {
    public let mode: RuntimeUpdateMode
    public let compatibilityDecision: CompatibilityDecision
    public let consentVersion: Int?
    public let helperAuthorized: Bool
    public let activity: RuntimeActivitySnapshot

    public init(
        mode: RuntimeUpdateMode,
        compatibilityDecision: CompatibilityDecision,
        consentVersion: Int?,
        helperAuthorized: Bool,
        activity: RuntimeActivitySnapshot
    ) {
        self.mode = mode
        self.compatibilityDecision = compatibilityDecision
        self.consentVersion = consentVersion
        self.helperAuthorized = helperAuthorized
        self.activity = activity
    }
}

public struct RuntimeUpdatePolicy: Sendable {
    public static let currentConsentVersion = 1

    public init() {}

    public func action(for input: RuntimeUpdatePolicyInput) -> RuntimeUpdateAction {
        guard case .allow = input.compatibilityDecision else {
            if case let .hold(reason) = input.compatibilityDecision {
                return .held(reason)
            }
            return .held(.catalogInvalid)
        }

        switch input.mode {
        case .checkOnly:
            return .notify
        case .downloadAndNotify:
            return .downloadThenNotify
        case .automaticWhenIdle:
            guard input.consentVersion == Self.currentConsentVersion, input.helperAuthorized else {
                return .pending(.authorizationRequired)
            }
            guard input.activity.isIdle else {
                return .pending(.workActive)
            }
            return .install
        }
    }
}

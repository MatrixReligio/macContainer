import Foundation
import Security

public enum CodeSigningRequirements {
    public static let app = requirement(bundleIdentifier: "container.matrixreligio.com")
    public static let helper = requirement(bundleIdentifier: "container.matrixreligio.com.helper")

    private static func requirement(bundleIdentifier: String) -> String {
        #"anchor apple generic and identifier "\#(bundleIdentifier)" and certificate leaf[subject.OU] = "4DUQGD879H""#
    }
}

public struct CallerConnectionContext: Equatable, Sendable {
    public let processIdentifier: Int32
    public let effectiveUserIdentifier: UInt32
    public let connectionRequirementEnforced: Bool

    public init(
        processIdentifier: Int32,
        effectiveUserIdentifier: UInt32,
        connectionRequirementEnforced: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.effectiveUserIdentifier = effectiveUserIdentifier
        self.connectionRequirementEnforced = connectionRequirementEnforced
    }
}

public struct SignedPeerIdentity: Equatable, Sendable {
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public let hardenedRuntime: Bool
    public let adHoc: Bool
    public let designatedRequirementSatisfied: Bool

    public init(
        bundleIdentifier: String,
        teamIdentifier: String,
        hardenedRuntime: Bool,
        adHoc: Bool,
        designatedRequirementSatisfied: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.hardenedRuntime = hardenedRuntime
        self.adHoc = adHoc
        self.designatedRequirementSatisfied = designatedRequirementSatisfied
    }
}

public protocol CallerIdentityInspecting: Sendable {
    func inspect(_ context: CallerConnectionContext, requirement: String) throws -> SignedPeerIdentity
}

public struct CallerValidator: Sendable {
    private let inspector: any CallerIdentityInspecting
    private let expectedBundleIdentifier: String
    private let expectedTeamIdentifier: String
    private let requirement: String

    public init(
        inspector: any CallerIdentityInspecting = SecurityCallerIdentityInspector(),
        expectedBundleIdentifier: String = "container.matrixreligio.com",
        expectedTeamIdentifier: String = "4DUQGD879H",
        requirement: String = CodeSigningRequirements.app
    ) {
        self.inspector = inspector
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self.expectedTeamIdentifier = expectedTeamIdentifier
        self.requirement = requirement
    }

    public func validate(_ context: CallerConnectionContext) throws -> SignedPeerIdentity {
        guard context.connectionRequirementEnforced else {
            throw HelperAuthorizationError.connectionNotBoundToRequirement
        }
        guard context.processIdentifier > 0 else { throw HelperAuthorizationError.missingPeerProcess }
        let identity = try inspector.inspect(context, requirement: requirement)
        guard identity.bundleIdentifier == expectedBundleIdentifier else {
            throw HelperAuthorizationError.bundleIdentifierMismatch
        }
        guard identity.teamIdentifier == expectedTeamIdentifier else {
            throw HelperAuthorizationError.teamIdentifierMismatch
        }
        guard identity.hardenedRuntime else { throw HelperAuthorizationError.hardenedRuntimeRequired }
        guard !identity.adHoc else { throw HelperAuthorizationError.adHocSignature }
        guard identity.designatedRequirementSatisfied else {
            throw HelperAuthorizationError.designatedRequirementMismatch
        }
        return identity
    }

    public func validate(_ connection: NSXPCConnection) throws -> SignedPeerIdentity {
        connection.setCodeSigningRequirement(requirement)
        return try validate(CallerConnectionContext(
            processIdentifier: connection.processIdentifier,
            effectiveUserIdentifier: connection.effectiveUserIdentifier,
            connectionRequirementEnforced: true
        ))
    }
}

public struct SecurityCallerIdentityInspector: CallerIdentityInspecting {
    public init() {}

    public func inspect(
        _ context: CallerConnectionContext,
        requirement requirementText: String
    ) throws -> SignedPeerIdentity {
        var code: SecCode?
        var processIdentifier = context.processIdentifier
        guard let processNumber = CFNumberCreate(nil, .sInt32Type, &processIdentifier) else {
            throw HelperAuthorizationError.codeIdentityUnavailable
        }
        let attributes = [kSecGuestAttributePid: processNumber] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            throw HelperAuthorizationError.codeIdentityUnavailable
        }

        var requirement: SecRequirement?
        guard let requirementString = CFStringCreateWithCString(
            nil,
            requirementText,
            CFStringBuiltInEncodings.UTF8.rawValue
        ) else {
            throw HelperAuthorizationError.invalidRequirement
        }
        let requirementStatus = SecRequirementCreateWithString(
            requirementString,
            [],
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            throw HelperAuthorizationError.invalidRequirement
        }
        let validityFlags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate | kSecCSCheckAllArchitectures))
        let requirementSatisfied = SecCodeCheckValidity(code, validityFlags, requirement) == errSecSuccess

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            throw HelperAuthorizationError.codeIdentityUnavailable
        }
        var information: CFDictionary?
        let informationFlags = SecCSFlags(rawValue: UInt32(
            kSecCSSigningInformation | kSecCSRequirementInformation
        ))
        guard SecCodeCopySigningInformation(staticCode, informationFlags, &information) == errSecSuccess,
              let dictionary = information as? [CFString: Any],
              let bundleIdentifier = dictionary[kSecCodeInfoIdentifier] as? String,
              let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier] as? String,
              let flagValue = dictionary[kSecCodeInfoFlags] as? UInt32
        else {
            throw HelperAuthorizationError.codeIdentityUnavailable
        }
        let flags = SecCodeSignatureFlags(rawValue: flagValue)
        return SignedPeerIdentity(
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier,
            hardenedRuntime: flags.contains(.runtime),
            adHoc: flags.contains(.adhoc),
            designatedRequirementSatisfied: requirementSatisfied
        )
    }
}

public enum HelperAuthorizationError: Error, Equatable, Sendable {
    case adHocSignature
    case bundleIdentifierMismatch
    case codeIdentityUnavailable
    case connectionNotBoundToRequirement
    case designatedRequirementMismatch
    case hardenedRuntimeRequired
    case invalidRequirement
    case missingPeerProcess
    case teamIdentifierMismatch
}

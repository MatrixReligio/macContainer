import Foundation

public enum ResidueStatus: String, Codable, Equatable, Sendable {
    case present
    case absent
    case unverifiable
}

public struct ResidueItem: Codable, Equatable, Sendable {
    public let kind: ResidueKind
    public let redactedLocation: String
    public let status: ResidueStatus
    public let recoveryKey: String

    public init(
        kind: ResidueKind,
        redactedLocation: String,
        status: ResidueStatus,
        recoveryKey: String
    ) {
        self.kind = kind
        self.redactedLocation = redactedLocation
        self.status = status
        self.recoveryKey = recoveryKey
    }
}

public struct ResidueReport: Codable, Equatable, Sendable {
    public let items: [ResidueItem]

    public var isEmpty: Bool {
        items.count == ResidueKind.allCases.count && items.allSatisfy { $0.status == .absent }
    }

    public var remainingItems: [ResidueItem] {
        items.filter { $0.status != .absent }
    }

    public init(items: [ResidueItem]) {
        self.items = items
    }

    public static func unverifiableForAll(recoveryKey: String) -> Self {
        Self(items: ResidueInventory.expectations.map { expectation in
            ResidueItem(
                kind: expectation.kind,
                redactedLocation: expectation.redactedLocation,
                status: .unverifiable,
                recoveryKey: recoveryKey
            )
        })
    }
}

public struct ResidueExpectation: Equatable, Sendable {
    public let kind: ResidueKind
    public let redactedLocation: String
    public let recoveryKey: String

    public init(kind: ResidueKind, redactedLocation: String, recoveryKey: String) {
        self.kind = kind
        self.redactedLocation = redactedLocation
        self.recoveryKey = recoveryKey
    }
}

public enum ResidueInventory {
    public static let expectations: [ResidueExpectation] = [
        .init(
            kind: .launchService,
            redactedLocation: "launchd:com.apple.container.*",
            recoveryKey: "uninstall.recovery.launch-service"
        ),
        .init(
            kind: .process,
            redactedLocation: "process:reviewed-runtime-payload",
            recoveryKey: "uninstall.recovery.process"
        ),
        .init(
            kind: .receipt,
            redactedLocation: "receipt:com.apple.container-installer",
            recoveryKey: "uninstall.recovery.receipt"
        ),
        .init(
            kind: .receiptPayload,
            redactedLocation: "/usr/local/{reviewed-container-payload}",
            recoveryKey: "uninstall.recovery.payload"
        ),
        .init(
            kind: .applicationSupport,
            redactedLocation: "<home>/Library/Application Support/com.apple.container",
            recoveryKey: "uninstall.recovery.application-support"
        ),
        .init(
            kind: .configuration,
            redactedLocation: "<home>/.config/container",
            recoveryKey: "uninstall.recovery.configuration"
        ),
        .init(
            kind: .defaultsDomain,
            redactedLocation: "defaults:com.apple.container.defaults",
            recoveryKey: "uninstall.recovery.defaults"
        ),
        .init(
            kind: .registryCredential,
            redactedLocation: "keychain:com.apple.container.registry",
            recoveryKey: "uninstall.recovery.registry-credential"
        ),
        .init(
            kind: .resolver,
            redactedLocation: "/etc/resolver/containerization.*",
            recoveryKey: "uninstall.recovery.resolver"
        ),
        .init(
            kind: .packetFilter,
            redactedLocation: "pf:com.apple.container",
            recoveryKey: "uninstall.recovery.packet-filter"
        ),
        .init(
            kind: .downloadedPackage,
            redactedLocation: "<app-support>/RuntimePackages",
            recoveryKey: "uninstall.recovery.downloaded-package"
        ),
        .init(
            kind: .rollbackPoint,
            redactedLocation: "<app-support>/Rollback",
            recoveryKey: "uninstall.recovery.rollback-point"
        ),
        .init(
            kind: .testFixture,
            redactedLocation: "<app-support>/PhysicalTests",
            recoveryKey: "uninstall.recovery.test-fixture"
        ),
        .init(
            kind: .downloadCache,
            redactedLocation: "<caches>/container.matrixreligio.com/Runtime",
            recoveryKey: "uninstall.recovery.download-cache"
        ),
        .init(
            kind: .runtimeOwnedDirectory,
            redactedLocation: "/usr/local/libexec/container",
            recoveryKey: "uninstall.recovery.runtime-directory"
        )
    ]
}

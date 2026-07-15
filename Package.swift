// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacContainerCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MCModel", targets: ["MCModel"]),
        .library(name: "MCContracts", targets: ["MCContracts"]),
        .library(name: "MCTemplates", targets: ["MCTemplates"]),
        .library(name: "MCContainerBridge", targets: ["MCContainerBridge"]),
        .library(name: "MCCompatibility", targets: ["MCCompatibility"]),
        .library(name: "MCSystemLifecycle", targets: ["MCSystemLifecycle"]),
        .library(name: "MCAppCore", targets: ["MCAppCore"]),
        .executable(name: "mc-verify-package", targets: ["MCVerifyPackage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/container.git", exact: "1.1.0"),
        .package(url: "https://github.com/apple/containerization.git", exact: "0.35.0"),
        .package(url: "https://github.com/mattt/swift-toml.git", exact: "2.0.0"),
    ],
    targets: [
        .target(name: "MCModel"),
        .target(
            name: "MCContracts",
            dependencies: ["MCModel"],
            resources: [.process("Resources")]
        ),
        .target(name: "MCTemplates", dependencies: ["MCModel", "MCContracts"]),
        .target(
            name: "MCContainerBridge",
            dependencies: [
                "MCModel",
                "MCContracts",
                .product(name: "ContainerAPIClient", package: "container"),
                .product(name: "ContainerBuild", package: "container"),
                .product(name: "ContainerNetworkClient", package: "container"),
                .product(name: "ContainerPersistence", package: "container"),
                .product(name: "ContainerPlugin", package: "container"),
                .product(name: "ContainerResource", package: "container"),
                .product(name: "ContainerXPC", package: "container"),
                .product(name: "MachineAPIClient", package: "container"),
                .product(name: "TerminalProgress", package: "container"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationArchive", package: "containerization"),
                .product(name: "TOML", package: "swift-toml"),
            ]
        ),
        .target(
            name: "MCCompatibility",
            dependencies: ["MCModel", "MCContracts", "MCContainerBridge"]
        ),
        .target(
            name: "MCSystemLifecycle",
            dependencies: ["MCModel", "MCContracts", "MCContainerBridge", "MCCompatibility"]
        ),
        .target(
            name: "MCAppCore",
            dependencies: [
                "MCModel",
                "MCContracts",
                "MCTemplates",
                "MCContainerBridge",
                "MCCompatibility",
                "MCSystemLifecycle",
            ]
        ),
        .executableTarget(
            name: "MCVerifyPackage",
            dependencies: ["MCSystemLifecycle"],
            path: "Tools/MCVerifyPackage"
        ),
        .target(
            name: "TestSupport",
            dependencies: ["MCModel", "MCContracts", "MCContainerBridge", "MCCompatibility", "MCSystemLifecycle"],
            path: "Tests/TestSupport"
        ),
        .testTarget(name: "MCModelTests", dependencies: ["MCModel", "TestSupport"]),
        .testTarget(name: "MCContractsTests", dependencies: ["MCContracts", "TestSupport"]),
        .testTarget(name: "MCTemplatesTests", dependencies: ["MCTemplates", "TestSupport"]),
        .testTarget(
            name: "MCContainerBridgeTests",
            dependencies: ["MCContainerBridge", "MCContracts", "MCModel", "TestSupport"]
        ),
        .testTarget(name: "MCCompatibilityTests", dependencies: ["MCCompatibility", "TestSupport"]),
        .testTarget(name: "MCSystemLifecycleTests", dependencies: ["MCSystemLifecycle", "TestSupport"]),
        .testTarget(name: "MCAppCoreTests", dependencies: ["MCAppCore", "TestSupport"]),
    ]
)

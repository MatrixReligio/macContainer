// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacContainerCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MCModel", targets: ["MCModel"]),
    ],
    targets: [
        .target(name: "MCModel"),
        .testTarget(name: "MCModelTests", dependencies: ["MCModel"]),
    ]
)

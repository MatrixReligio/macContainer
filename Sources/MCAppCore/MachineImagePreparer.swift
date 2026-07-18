import Foundation
import MCContainerBridge
import MCModel

public enum MachineImageDefaults {
    public static let reference = "local/maccontainer-machine-alpine:3.22"
    public static let baseReference = "alpine:3.22"
}

public protocol MachineImagePreparing: Sendable {
    func prepareIfNeeded(imageReference: String) async throws
}

public actor SimulatedMachineImagePreparer: MachineImagePreparing {
    public init() {}

    public func prepareIfNeeded(imageReference _: String) async throws {}
}

public actor ProductionMachineImagePreparer: MachineImagePreparing {
    private let bridge: any RuntimeBridge
    private let fileManager: FileManager

    public init(
        bridge: (any RuntimeBridge)? = nil,
        fileManager: FileManager = .default
    ) {
        self.bridge = bridge ?? AppleRuntimeBridge()
        self.fileManager = fileManager
    }

    public func prepareIfNeeded(imageReference: String) async throws {
        guard imageReference == MachineImageDefaults.reference else { return }
        if await (try? bridge.images.inspect(reference: imageReference)) != nil {
            return
        }

        let context = fileManager.temporaryDirectory
            .appendingPathComponent("maccontainer-machine-image-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: context, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: context) }

        guard let bundledContainerfile = MachineImageDefaults.bundledContainerfileURL() else {
            throw MachineImagePreparationError.bundledDefinitionMissing
        }
        let containerfile = context.appendingPathComponent("Containerfile")
        try fileManager.copyItem(at: bundledContainerfile, to: containerfile)
        let stream = try await bridge.builds.build(.init(
            context: context,
            dockerfile: containerfile,
            tags: [MachineImageDefaults.reference],
            platforms: ["linux/arm64"]
        ))
        for try await _ in stream {
            try Task.checkCancellation()
        }
        _ = try await bridge.images.inspect(reference: imageReference)
    }
}

extension MachineImageDefaults {
    static func bundledContainerfileURL() -> URL? {
        Bundle.module.url(forResource: "AlpineMachine", withExtension: "containerfile")
    }
}

public enum MachineImagePreparationError: Error, Equatable, Sendable {
    case bundledDefinitionMissing
}

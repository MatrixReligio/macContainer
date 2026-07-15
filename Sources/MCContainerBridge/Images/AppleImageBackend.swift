import ContainerAPIClient
import ContainerizationOCI
import ContainerPersistence
import Foundation
import MCModel
import TerminalProgress

public enum AppleImageBackendError: Error, Equatable, Sendable {
    case protectedInfrastructureImage
}

public struct AppleImageBackend: ImageBackend, Sendable {
    public init() {}

    public func list() async throws -> [ImageDetail] {
        try await ClientImage.list().asyncMap { image in
            try await ImageDetail(
                summary: ImageSummary(
                    reference: image.reference,
                    digest: image.digest,
                    sizeBytes: ClientImage.getFullImageSize(image: image)
                )
            )
        }
    }

    public func pull(
        _ request: ImageTransferRequest,
        progress: @escaping @Sendable (BackendTransferProgress) async -> Void
    ) async throws -> ImageDetail {
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let platform = try request.platform.map { try Platform(from: $0) }
        let translator = AppleTransferProgressTranslator(defaultPhase: "pull")
        let handler = Self.progressHandler(translator: translator, progress: progress)
        let image = try await ClientImage.pull(
            reference: request.reference,
            platform: platform,
            scheme: .auto,
            containerSystemConfig: configuration,
            progressUpdate: handler,
            maxConcurrentDownloads: 3
        )
        if request.unpack {
            await translator.setPhase("unpack")
            try await image.unpack(platform: platform, progressUpdate: handler)
        }
        return try await Self.detail(image)
    }

    public func push(
        _ request: ImageTransferRequest,
        progress: @escaping @Sendable (BackendTransferProgress) async -> Void
    ) async throws {
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let platform = try request.platform.map { try Platform(from: $0) }
        let image = try await ClientImage.get(
            reference: request.reference,
            containerSystemConfig: configuration
        )
        let translator = AppleTransferProgressTranslator(defaultPhase: "push")
        try await image.push(
            platform: platform,
            scheme: .auto,
            containerSystemConfig: configuration,
            progressUpdate: Self.progressHandler(translator: translator, progress: progress)
        )
    }

    public func save(references: [String], destination: URL) async throws {
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        try await ClientImage.save(
            references: references,
            out: destination.path,
            containerSystemConfig: configuration
        )
    }

    public func load(source: URL) async throws -> BackendImageLoadResult {
        let result = try await ClientImage.load(from: source.path, force: false)
        return try await BackendImageLoadResult(
            images: result.images.asyncMap(Self.detail),
            rejectedMembers: result.rejectedMembers
        )
    }

    public func tag(source: String, target: String) async throws {
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let existing = try await ClientImage.get(
            reference: source,
            containerSystemConfig: configuration
        )
        let canonicalTarget = try ClientImage.normalizeReference(
            target,
            containerSystemConfig: configuration
        )
        try await existing.tag(new: canonicalTarget)
    }

    public func delete(reference: String) async throws {
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let image = try await ClientImage.get(
            reference: reference,
            containerSystemConfig: configuration
        )
        guard !Utility.isInfraImage(
            name: image.reference,
            builderImage: configuration.build.image,
            initImage: configuration.vminit.image
        ) else {
            throw AppleImageBackendError.protectedInfrastructureImage
        }
        try await ClientImage.delete(reference: image.reference, garbageCollect: true)
    }

    public func prune() async throws -> PruneResult {
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let candidates = try await ClientImage.list().filter { image in
            !Self.hasTag(image.reference)
                && !Utility.isInfraImage(
                    name: image.reference,
                    builderImage: configuration.build.image,
                    initImage: configuration.vminit.image
                )
        }
        var deletedReferences: [String] = []
        for image in candidates {
            try Task.checkCancellation()
            do {
                try await ClientImage.delete(reference: image.reference, garbageCollect: false)
                deletedReferences.append(image.reference)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        let result = try await ClientImage.cleanUpOrphanedBlobs()
        return PruneResult(
            deletedIDs: deletedReferences + result.0.sorted(),
            reclaimedBytes: Int64(clamping: result.1)
        )
    }

    public func inspect(reference: String) async throws -> ImageDetail {
        let configuration: ContainerSystemConfig = try await ConfigurationLoader.load()
        let image = try await ClientImage.get(
            reference: reference,
            containerSystemConfig: configuration
        )
        return try await Self.detail(image)
    }

    private static func detail(_ image: ClientImage) async throws -> ImageDetail {
        let index = try await image.index()
        let annotations = index.annotations ?? [:]
        return try await ImageDetail(
            summary: ImageSummary(
                reference: image.reference,
                digest: image.digest,
                sizeBytes: ClientImage.getFullImageSize(image: image)
            ),
            platforms: index.manifests.compactMap { $0.platform?.description }.sorted(),
            redactedMetadata: annotations.filter { key, _ in
                !Self.sensitiveMetadataKey(key)
            }
        )
    }

    private static func sensitiveMetadataKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return ["token", "secret", "password", "credential", "authorization"].contains {
            normalized.contains($0)
        }
    }

    private static func hasTag(_ reference: String) -> Bool {
        guard let parsed = try? Reference.parse(reference) else {
            return false
        }
        return parsed.tag?.isEmpty == false
    }

    private static func progressHandler(
        translator: AppleTransferProgressTranslator,
        progress: @escaping @Sendable (BackendTransferProgress) async -> Void
    ) -> ProgressUpdateHandler {
        { events in
            let update = await translator.apply(events)
            await progress(update)
        }
    }
}

private actor AppleTransferProgressTranslator {
    private var phase: String
    private var completedBytes: Int64 = 0
    private var totalBytes: Int64?
    private var completedItems = 0
    private var totalItems: Int?

    init(defaultPhase: String) {
        phase = defaultPhase
    }

    func setPhase(_ value: String) {
        phase = value
        completedBytes = 0
        totalBytes = nil
        completedItems = 0
        totalItems = nil
    }

    func apply(_ events: [ProgressUpdateEvent]) -> BackendTransferProgress {
        for event in events {
            if applyDescription(event) || applyItems(event) || applySize(event) {
                continue
            }
        }
        return BackendTransferProgress(
            phase: phase,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            completedLayers: completedItems,
            totalLayers: totalItems
        )
    }

    private func applyDescription(_ event: ProgressUpdateEvent) -> Bool {
        switch event {
        case let .setDescription(value), let .setSubDescription(value):
            phase = value
            return true
        default:
            return false
        }
    }

    private func applyItems(_ event: ProgressUpdateEvent) -> Bool {
        switch event {
        case let .addItems(value): completedItems += value
        case let .setItems(value): completedItems = value
        case let .addTotalItems(value): totalItems = (totalItems ?? 0) + value
        case let .setTotalItems(value): totalItems = value
        default: return false
        }
        return true
    }

    private func applySize(_ event: ProgressUpdateEvent) -> Bool {
        switch event {
        case let .addSize(value): completedBytes += value
        case let .setSize(value): completedBytes = value
        case let .addTotalSize(value): totalBytes = (totalBytes ?? 0) + value
        case let .setTotalSize(value): totalBytes = value
        default: return false
        }
        return true
    }
}

private extension Sequence where Element: Sendable {
    func asyncMap<Transformed: Sendable>(
        _ transform: (Element) async throws -> Transformed
    ) async rethrows -> [Transformed] {
        var result: [Transformed] = []
        result.reserveCapacity(underestimatedCount)
        for element in self {
            try await result.append(transform(element))
        }
        return result
    }
}

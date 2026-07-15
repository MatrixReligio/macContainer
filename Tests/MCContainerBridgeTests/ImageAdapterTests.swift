import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Image adapter")
struct ImageAdapterTests {
    @Test func `all nine operations delegate and preserve stable batch results`() async throws {
        let detail = ImageDetail(summary: ImageSummary(reference: "example:latest", digest: "sha256:abc"))
        let backend = FakeImageBackend(images: [detail], deleteFailures: ["broken:latest"])
        let adapter = ImageAdapter(client: backend)
        let archive = URL(fileURLWithPath: "/private/tmp/MacContainer-images.tar")

        _ = try await adapter.list()
        _ = try await collect(adapter.pull(ImageTransferRequest(reference: "example:latest")))
        _ = try await collect(adapter.push(ImageTransferRequest(reference: "example:latest")))
        try await adapter.save(references: ["example:latest"], destination: archive)
        _ = try await adapter.load(source: archive)
        try await adapter.tag(source: "example:latest", target: "example:test")
        let deleted = try await adapter.delete(references: ["example:test", "broken:latest"])
        _ = try await adapter.prune()
        _ = try await adapter.inspect(reference: "example:latest")

        #expect(await backend.operationIDs == [
            "list", "pull", "push", "save", "load", "tag", "delete:example:test",
            "delete:broken:latest", "prune", "inspect"
        ])
        #expect(deleted.map(\.succeeded) == [true, false])
    }

    @Test func `transfer progress never regresses and unpack is included`() async throws {
        let backend = FakeImageBackend(
            images: [],
            transferUpdates: [
                BackendTransferProgress(
                    phase: "download", completedBytes: 10, totalBytes: 100,
                    completedLayers: 1, totalLayers: 2
                ),
                BackendTransferProgress(
                    phase: "download", completedBytes: 5, totalBytes: 90,
                    completedLayers: 0, totalLayers: 2
                ),
                BackendTransferProgress(
                    phase: "unpack", completedBytes: 40, totalBytes: 100,
                    completedLayers: 2, totalLayers: 2
                )
            ]
        )
        let adapter = ImageAdapter(client: backend)

        let values = try await collect(
            adapter.pull(ImageTransferRequest(reference: "repo/image@sha256:abc", unpack: true))
        )

        #expect(values.map(\.completedBytes) == [10, 10, 40])
        #expect(values.map(\.completedLayers) == [1, 1, 2])
        #expect(values.last?.phase == "unpack")
        #expect(await backend.pullRequests.first?.reference == "repo/image@sha256:abc")
        #expect(await backend.pullRequests.first?.unpack == true)
    }

    @Test func `load rejects an archive with traversal members`() async {
        let backend = FakeImageBackend(
            images: [],
            loadResult: BackendImageLoadResult(images: [], rejectedMembers: ["../../escape"])
        )
        let adapter = ImageAdapter(client: backend)

        await #expect(throws: ImageAdapterError.archiveContainsRejectedMembers) {
            try await adapter.load(source: URL(fileURLWithPath: "/private/tmp/untrusted.tar"))
        }
    }

    @Test func `batch deletion preserves task cancellation`() async {
        let backend = FakeImageBackend(images: [])
        let adapter = ImageAdapter(client: backend)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await adapter.delete(references: ["example:latest"])
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await backend.operationIDs.isEmpty)
    }

    private func collect<Element: Sendable>(
        _ stream: AsyncThrowingStream<Element, any Error>
    ) async throws -> [Element] {
        var result: [Element] = []
        for try await element in stream {
            result.append(element)
        }
        return result
    }
}

private enum FakeImageError: Error {
    case failed
}

private actor FakeImageBackend: ImageBackend {
    private let images: [ImageDetail]
    private let deleteFailures: Set<String>
    private let transferUpdates: [BackendTransferProgress]
    private let loadResult: BackendImageLoadResult
    private(set) var operationIDs: [String] = []
    private(set) var pullRequests: [ImageTransferRequest] = []

    init(
        images: [ImageDetail],
        deleteFailures: Set<String> = [],
        transferUpdates: [BackendTransferProgress] = [],
        loadResult: BackendImageLoadResult? = nil
    ) {
        self.images = images
        self.deleteFailures = deleteFailures
        self.transferUpdates = transferUpdates
        self.loadResult = loadResult ?? BackendImageLoadResult(images: images, rejectedMembers: [])
    }

    func list() async throws -> [ImageDetail] {
        operationIDs.append("list")
        return images
    }

    func pull(
        _ request: ImageTransferRequest,
        progress: @escaping @Sendable (BackendTransferProgress) async -> Void
    ) async throws -> ImageDetail {
        operationIDs.append("pull")
        pullRequests.append(request)
        for update in transferUpdates {
            try Task.checkCancellation()
            await progress(update)
        }
        return images.first ?? ImageDetail(summary: ImageSummary(reference: request.reference))
    }

    func push(
        _ request: ImageTransferRequest,
        progress: @escaping @Sendable (BackendTransferProgress) async -> Void
    ) async throws {
        operationIDs.append("push")
        for update in transferUpdates {
            try Task.checkCancellation()
            await progress(update)
        }
    }

    func save(references _: [String], destination _: URL) async throws {
        operationIDs.append("save")
    }

    func load(source _: URL) async throws -> BackendImageLoadResult {
        operationIDs.append("load")
        return loadResult
    }

    func tag(source _: String, target _: String) async throws {
        operationIDs.append("tag")
    }

    func delete(reference: String) async throws {
        operationIDs.append("delete:\(reference)")
        if deleteFailures.contains(reference) {
            throw FakeImageError.failed
        }
    }

    func prune() async throws -> PruneResult {
        operationIDs.append("prune")
        return PruneResult(deletedIDs: ["unused"], reclaimedBytes: 42)
    }

    func inspect(reference _: String) async throws -> ImageDetail {
        operationIDs.append("inspect")
        return images[0]
    }
}

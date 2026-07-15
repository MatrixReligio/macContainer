import Foundation
@testable import MCContainerBridge
import MCModel
import Testing

@Suite("Build adapter")
struct BuildAdapterTests {
    @Test func `maps a confined build and redacts secret values from progress`() async throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let secret = fixture.root.appendingPathComponent("token.txt")
        try Data("super-secret".utf8).write(to: secret)
        let backend = FakeBuildBackend(updates: [
            BuildProgress(
                phase: "super-secret phase",
                message: "using super-secret",
                fractionCompleted: 0.7
            ),
            BuildProgress(phase: "build", message: "regressed", fractionCompleted: 0.2)
        ])
        let adapter = BuildAdapter(client: backend, buildID: { "stable-build" })
        let request = BuildRequest(
            context: fixture.context,
            dockerfile: fixture.dockerfile,
            tags: ["example/app:latest"],
            platforms: ["linux/arm64"],
            buildArguments: [KeyValue(key: "MODE", value: "release")],
            secretReferences: [BuildSecretReference(id: "token", source: secret)],
            outputs: [KeyValue(key: "type", value: "oci")],
            cacheImports: ["type=registry,ref=cache-in"],
            cacheExports: ["type=registry,ref=cache-out"]
        )

        let progress = try await collect(adapter.build(request))
        let plan = try #require(await backend.plans.first)

        #expect(plan.id == "stable-build")
        #expect(plan.context == fixture.context.resolvingSymlinksInPath())
        #expect(plan.dockerfile == Data("FROM scratch\n".utf8))
        #expect(plan.tags == request.tags)
        #expect(plan.platforms == request.platforms)
        #expect(plan.buildArguments == request.buildArguments)
        #expect(plan.secrets["token"] == Data("super-secret".utf8))
        #expect(plan.outputs == request.outputs)
        #expect(plan.cacheImports == request.cacheImports)
        #expect(plan.cacheExports == request.cacheExports)
        #expect(progress.map(\.fractionCompleted) == [0.7, 0.7])
        #expect(progress.allSatisfy { !$0.message.contains("super-secret") })
        #expect(progress.allSatisfy { !$0.phase.contains("super-secret") })
    }

    @Test func `rejects a dockerfile that escapes through a symlink before backend access`() async {
        do {
            let fixture = try BuildFixture()
            defer { fixture.remove() }
            let outside = fixture.root.appendingPathComponent("outside.Dockerfile")
            try Data("FROM scratch\n".utf8).write(to: outside)
            let link = fixture.context.appendingPathComponent("Dockerfile.link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            let backend = FakeBuildBackend()
            let adapter = BuildAdapter(client: backend)

            await #expect(throws: BuildAdapterError.dockerfileOutsideContext) {
                _ = try await collect(
                    adapter.build(BuildRequest(context: fixture.context, dockerfile: link))
                )
            }
            #expect(await backend.plans.isEmpty)
        } catch {
            Issue.record("fixture setup failed: \(type(of: error))")
        }
    }

    @Test func `cancelling the progress consumer cancels backend work`() async throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let backend = FakeBuildBackend(waitForCancellation: true)
        let adapter = BuildAdapter(client: backend)
        let stream = try await adapter.build(BuildRequest(context: fixture.context))
        let consumer = Task {
            for try await _ in stream {}
        }

        await backend.waitUntilStarted()
        consumer.cancel()
        _ = await consumer.result
        await backend.waitUntilCancelled()

        #expect(await backend.observedCancellation)
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

private final class BuildFixture {
    let parent: URL
    let root: URL
    let context: URL
    let dockerfile: URL

    init() throws {
        parent = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-temp")
        root = parent.appendingPathComponent("build-\(UUID().uuidString)")
        context = root.appendingPathComponent("context")
        dockerfile = context.appendingPathComponent("Dockerfile")
        try FileManager.default.createDirectory(at: context, withIntermediateDirectories: true)
        try Data("FROM scratch\n".utf8).write(to: dockerfile)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        if (try? FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: parent)
        }
    }
}

private actor FakeBuildBackend: BuildBackend {
    private let updates: [BuildProgress]
    private let waitForCancellation: Bool
    private var started = false
    private var cancelled = false
    private(set) var plans: [BuildPlan] = []
    private(set) var observedCancellation = false

    init(updates: [BuildProgress] = [], waitForCancellation: Bool = false) {
        self.updates = updates
        self.waitForCancellation = waitForCancellation
    }

    func build(
        _ plan: BuildPlan,
        progress: @escaping @Sendable (BuildProgress) async -> Void
    ) async throws {
        plans.append(plan)
        started = true
        for update in updates {
            await progress(update)
        }
        guard waitForCancellation else {
            return
        }
        do {
            while true {
                try await Task.sleep(for: .seconds(10))
            }
        } catch is CancellationError {
            observedCancellation = true
            cancelled = true
            throw CancellationError()
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func waitUntilCancelled() async {
        while !cancelled {
            await Task.yield()
        }
    }
}

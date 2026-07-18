import Foundation
@testable import MCAppCore
import MCModel
import Testing

@MainActor
@Suite("Runtime resource browser")
struct RuntimeResourceBrowserControllerTests {
    @Test func `refresh replaces fixtures with provider snapshots`() async {
        let provider = RecordingRuntimeResourceProvider()
        let controller = RuntimeResourceBrowserController(
            provider: provider,
            activities: ActivityCenter()
        )

        await controller.refresh(.containers)

        #expect(controller.resources(for: .containers) == [
            .init(id: "live", name: "live", status: "Running", detail: "alpine:latest")
        ])
        #expect(await provider.loadedRoutes == [.containers])
    }

    @Test func `delete delegates exact IDs and refreshes authoritative list`() async {
        let provider = RecordingRuntimeResourceProvider()
        let controller = RuntimeResourceBrowserController(
            provider: provider,
            activities: ActivityCenter()
        )
        await controller.refresh(.containers)

        await controller.delete(.containers, ids: ["live"])

        #expect(await provider.deleted == [.init(route: .containers, ids: ["live"])])
        #expect(await provider.loadedRoutes == [.containers, .containers])
    }

    @Test func `provider failure is visible and never invents success`() async {
        let provider = RecordingRuntimeResourceProvider(fails: true)
        let controller = RuntimeResourceBrowserController(
            provider: provider,
            activities: ActivityCenter()
        )

        await controller.refresh(.images)

        #expect(controller.resources(for: .images).isEmpty)
        #expect(controller.errorCode(for: .images) == "resources.refresh.failed")
    }

    @Test func `machine start and stop delegate exact selection then refresh`() async {
        let provider = RecordingRuntimeResourceProvider()
        let controller = RuntimeResourceBrowserController(
            provider: provider,
            activities: ActivityCenter()
        )

        await controller.start(.machines, ids: ["machine-a"])
        await controller.stop(.machines, ids: ["machine-a"])

        #expect(await provider.mutations == [
            .init(action: .start, route: .machines, ids: ["machine-a"]),
            .init(action: .stop, route: .machines, ids: ["machine-a"])
        ])
        #expect(await provider.loadedRoutes == [.machines, .machines])
    }

    @Test func `machine configuration delegates typed values and refreshes`() async {
        let provider = RecordingRuntimeResourceProvider()
        let controller = RuntimeResourceBrowserController(
            provider: provider,
            activities: ActivityCenter()
        )
        let request = MachineSetRequest(
            resources: RuntimeResources(cpuCount: 6, memoryBytes: 8_589_934_592),
            homeMount: "ro",
            homeSharingConsent: HomeSharingConsent(token: UUID()),
            nestedVirtualization: true
        )

        await controller.configureMachine(id: "machine-a", request: request)

        #expect(await provider.configurations == [
            .init(id: "machine-a", request: request)
        ])
        #expect(await provider.loadedRoutes == [.machines])
    }
}

private actor RecordingRuntimeResourceProvider: RuntimeResourceProviding {
    enum MutationAction: Equatable, Sendable { case start, stop }

    struct Deletion: Equatable, Sendable {
        let route: AppRoute
        let ids: [String]
    }

    struct Mutation: Equatable, Sendable {
        let action: MutationAction
        let route: AppRoute
        let ids: [String]
    }

    struct Configuration: Equatable, Sendable {
        let id: String
        let request: MachineSetRequest
    }

    let fails: Bool
    var loadedRoutes: [AppRoute] = []
    var deleted: [Deletion] = []
    var mutations: [Mutation] = []
    var configurations: [Configuration] = []

    init(fails: Bool = false) {
        self.fails = fails
    }

    func load(_ route: AppRoute) async throws -> [RuntimeResourceSnapshot] {
        loadedRoutes.append(route)
        if fails {
            throw ResourceProviderTestError.failed
        }
        guard route == .containers, deleted.isEmpty else { return [] }
        return [.init(id: "live", name: "live", status: "Running", detail: "alpine:latest")]
    }

    func delete(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult] {
        if fails {
            throw ResourceProviderTestError.failed
        }
        deleted.append(.init(route: route, ids: ids))
        return ids.map { .init(resourceID: $0, outcome: .succeeded) }
    }

    func start(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult] {
        mutations.append(.init(action: .start, route: route, ids: ids))
        return ids.map { .init(resourceID: $0, outcome: .succeeded) }
    }

    func stop(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult] {
        mutations.append(.init(action: .stop, route: route, ids: ids))
        return ids.map { .init(resourceID: $0, outcome: .succeeded) }
    }

    func configureMachine(id: String, request: MachineSetRequest) async throws {
        configurations.append(.init(id: id, request: request))
    }
}

private enum ResourceProviderTestError: Error {
    case failed
}

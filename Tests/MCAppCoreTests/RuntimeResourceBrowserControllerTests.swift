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
}

private actor RecordingRuntimeResourceProvider: RuntimeResourceProviding {
    struct Deletion: Equatable, Sendable {
        let route: AppRoute
        let ids: [String]
    }

    let fails: Bool
    var loadedRoutes: [AppRoute] = []
    var deleted: [Deletion] = []

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
}

private enum ResourceProviderTestError: Error {
    case failed
}

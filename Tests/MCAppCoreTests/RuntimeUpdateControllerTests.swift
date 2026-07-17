import Foundation
@testable import MCAppCore
import MCSystemLifecycle
import Testing

@MainActor
@Suite("Runtime update controller")
struct RuntimeUpdateControllerTests {
    @Test func `manual check exposes intermediate and final service states`() async {
        let service = RecordingRuntimeUpdateManager()
        let controller = RuntimeUpdateController(service: service, initialState: .upToDate)

        await controller.checkNow()

        #expect(controller.state == .available(version: "1.1.0"))
        #expect(controller.isBusy == false)
        #expect(await service.checkCount == 1)
    }

    @Test func `explicit installation delegates only after an available candidate`() async {
        let service = RecordingRuntimeUpdateManager()
        let controller = RuntimeUpdateController(
            service: service,
            initialState: .available(version: "1.1.0")
        )

        await controller.installAvailable()

        #expect(controller.state == .upToDate)
        #expect(await service.installCount == 1)
    }

    @Test func `restores durable agent state when app launches`() async {
        let service = RecordingRuntimeUpdateManager(
            latest: .init(
                state: .pending(.workActive),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        )
        let controller = RuntimeUpdateController(service: service, initialState: .checking)

        await controller.restoreLatestStatus()

        #expect(controller.state == .pending(.workActive))
    }
}

private actor RecordingRuntimeUpdateManager: RuntimeUpdateManaging {
    var checkCount = 0
    var installCount = 0
    let latest: PersistedRuntimeUpdateStatus?

    init(latest: PersistedRuntimeUpdateStatus? = nil) {
        self.latest = latest
    }

    func check(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState {
        checkCount += 1
        await stateSink.publish(.checking)
        await stateSink.publish(.available(version: "1.1.0"))
        return .available(version: "1.1.0")
    }

    func installAvailable(stateSink: any RuntimeUpdateStateSink) async -> RuntimeUpdateState {
        installCount += 1
        await stateSink.publish(.installing(.targetProbes))
        await stateSink.publish(.upToDate)
        return .upToDate
    }

    func latestStatus() -> PersistedRuntimeUpdateStatus? {
        latest
    }
}

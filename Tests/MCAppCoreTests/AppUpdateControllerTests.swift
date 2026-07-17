import Foundation
@testable import MCAppCore
import Testing

@MainActor
@Suite("Application update policy")
struct AppUpdateControllerTests {
    @Test func `configures a daily signed application feed independently from runtime updates`() {
        let driver = RecordingAppUpdateDriver()
        let controller = AppUpdateController(driver: driver)

        #expect(controller.domain == .application)
        #expect(controller.domain != .appleContainerRuntime)
        #expect(AppUpdatePolicy.feedURL.absoluteString ==
            "https://github.com/matrixreligio/macContainer/releases/latest/download/appcast.xml")
        #expect(AppUpdatePolicy.scheduledCheckInterval == 86400)
        #expect(driver.automaticallyChecksForUpdates)
        #expect(driver.updateCheckInterval == 86400)
    }

    @Test func `automatic checks can be disabled without changing runtime update policy`() {
        let driver = RecordingAppUpdateDriver()
        let controller = AppUpdateController(driver: driver)

        controller.setAutomaticallyChecksForUpdates(false)

        #expect(controller.automaticallyChecksForUpdates == false)
        #expect(driver.automaticallyChecksForUpdates == false)
        #expect(controller.domain == .application)
    }

    @Test func `manual check delegates only while updater is ready`() {
        let driver = RecordingAppUpdateDriver()
        let controller = AppUpdateController(driver: driver)

        #expect(controller.checkNow())
        #expect(driver.manualCheckCount == 1)
        #expect(controller.state == .checking)

        driver.canCheckForUpdates = false
        #expect(controller.checkNow() == false)
        #expect(driver.manualCheckCount == 1)
        #expect(controller.state == .unavailable)
    }

    @Test func `update callbacks expose useful state and errors`() {
        let controller = AppUpdateController()

        controller.didFindUpdate(version: "0.2.0")
        #expect(controller.state == .available(version: "0.2.0"))

        controller.didFinishWithoutUpdate()
        #expect(controller.state == .upToDate)

        controller.didFail(message: "The signed appcast could not be loaded.")
        #expect(controller.state == .failed(message: "The signed appcast could not be loaded."))
    }

    @Test func `relaunch is postponed until drafts and activities are safe`() {
        let controller = AppUpdateController()
        var continuationCount = 0

        #expect(controller.postponeRelaunch(
            hasUnsavedWork: true,
            hasActiveOperations: false,
            continuation: { continuationCount += 1 }
        ))
        #expect(controller.relaunchSafety == .saveOrDiscardDraft)
        #expect(controller.resumeRelaunch(hasUnsavedWork: true, hasActiveOperations: false) == false)
        #expect(continuationCount == 0)

        #expect(controller.resumeRelaunch(hasUnsavedWork: false, hasActiveOperations: true) == false)
        #expect(controller.relaunchSafety == .waitForActivities)
        #expect(continuationCount == 0)

        #expect(controller.resumeRelaunch(hasUnsavedWork: false, hasActiveOperations: false))
        #expect(controller.relaunchSafety == .ready)
        #expect(continuationCount == 1)
    }

    @Test func `safe relaunch does not retain or invoke a continuation`() {
        let controller = AppUpdateController()
        var continuationCount = 0

        #expect(controller.postponeRelaunch(
            hasUnsavedWork: false,
            hasActiveOperations: false,
            continuation: { continuationCount += 1 }
        ) == false)
        #expect(controller.relaunchSafety == .ready)
        #expect(controller.hasPendingRelaunch == false)
        #expect(continuationCount == 0)
    }
}

@MainActor
private final class RecordingAppUpdateDriver: AppUpdateDriving {
    var automaticallyChecksForUpdates = true
    var updateCheckInterval: TimeInterval = 0
    var canCheckForUpdates = true
    private(set) var manualCheckCount = 0

    func checkForUpdates() {
        manualCheckCount += 1
    }
}

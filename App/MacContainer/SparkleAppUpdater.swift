import MCAppCore
import Sparkle

@MainActor
final class SparkleAppUpdater: NSObject, AppUpdateDriving, SPUUpdaterDelegate {
    private weak var state: AppState?
    private weak var appUpdateController: AppUpdateController?
    private var standardController: SPUStandardUpdaterController!

    init(state: AppState) {
        self.state = state
        appUpdateController = state.appUpdates
        super.init()
        standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { standardController.updater.automaticallyChecksForUpdates }
        set { standardController.updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { standardController.updater.updateCheckInterval }
        set { standardController.updater.updateCheckInterval = newValue }
    }

    var canCheckForUpdates: Bool {
        standardController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        standardController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        appUpdateController?.didFindUpdate(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        appUpdateController?.didFinishWithoutUpdate()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain, error.code == 1001 {
            appUpdateController?.didFinishWithoutUpdate()
        } else if error.domain == SUSparkleErrorDomain, error.code == 4007 {
            appUpdateController?.didCancel()
        } else {
            appUpdateController?.didFail(message: error.localizedDescription)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard let state, let appUpdateController else { return false }
        return appUpdateController.postponeRelaunch(
            hasUnsavedWork: state.hasUnsavedWork,
            hasActiveOperations: state.activities.hasActiveOperations,
            continuation: installHandler
        )
    }
}

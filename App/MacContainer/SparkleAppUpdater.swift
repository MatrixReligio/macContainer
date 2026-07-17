import MCAppCore
import Sparkle

@MainActor
final class SparkleAppUpdater: NSObject, AppUpdateDriving, SPUUpdaterDelegate {
    private weak var state: AppState?
    private weak var appUpdateController: AppUpdateController?
    private var standardController: SPUStandardUpdaterController!
    private let testFeedURL: URL?

    static var hasValidatedTestFeed: Bool {
        validatedTestFeedURL() != nil
    }

    init(state: AppState) {
        self.state = state
        appUpdateController = state.appUpdates
        testFeedURL = Self.validatedTestFeedURL()
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

    func feedURLString(for updater: SPUUpdater) -> String? {
        testFeedURL?.absoluteString
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

    private static func validatedTestFeedURL() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let rootArgument = arguments.first(where: { $0.hasPrefix("--sparkle-test-root=") }),
              let feedArgument = arguments.first(where: { $0.hasPrefix("--sparkle-test-feed-url=") })
        else { return nil }
        let root = String(rootArgument.dropFirst("--sparkle-test-root=".count))
        let feed = String(feedArgument.dropFirst("--sparkle-test-feed-url=".count))
        guard root.contains("/.artifacts/sparkle-test/"),
              ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]?.hasPrefix(root) == true,
              let url = URL(string: feed), url.scheme == "http", url.host == "127.0.0.1",
              url.port != nil, url.path == "/appcast.xml"
        else { return nil }
        return url
    }
}

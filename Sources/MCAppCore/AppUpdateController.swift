import Foundation
import Observation

public enum UpdateDomain: String, Equatable, Sendable {
    case application
    case appleContainerRuntime
}

public enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case available(version: String)
    case upToDate
    case unavailable
    case failed(message: String)
}

public enum AppUpdateRelaunchSafety: Equatable, Sendable {
    case ready
    case saveOrDiscardDraft
    case waitForActivities
}

public enum AppUpdatePolicy {
    public static let feedURL = URL(
        string: "https://github.com/matrixreligio/macContainer/releases/latest/download/appcast.xml"
    )!
    public static let scheduledCheckInterval: TimeInterval = 86400
}

@MainActor
public protocol AppUpdateDriving: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    var canCheckForUpdates: Bool { get }

    func checkForUpdates()
}

@MainActor
@Observable
public final class AppUpdateController {
    public let domain: UpdateDomain = .application
    public private(set) var state: AppUpdateState = .idle
    public private(set) var relaunchSafety: AppUpdateRelaunchSafety = .ready
    public private(set) var automaticallyChecksForUpdates: Bool

    @ObservationIgnored private weak var driver: (any AppUpdateDriving)?
    @ObservationIgnored private var pendingRelaunch: (() -> Void)?

    public var hasPendingRelaunch: Bool {
        pendingRelaunch != nil
    }

    public init(
        driver: (any AppUpdateDriving)? = nil,
        automaticallyChecksForUpdates: Bool = true
    ) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        attach(driver: driver)
    }

    public func attach(driver: (any AppUpdateDriving)?) {
        self.driver = driver
        guard let driver else { return }
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        driver.updateCheckInterval = AppUpdatePolicy.scheduledCheckInterval
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        driver?.automaticallyChecksForUpdates = enabled
    }

    @discardableResult
    public func checkNow() -> Bool {
        guard let driver, driver.canCheckForUpdates else {
            state = .unavailable
            return false
        }
        state = .checking
        driver.checkForUpdates()
        return true
    }

    public func didFindUpdate(version: String) {
        state = .available(version: version)
    }

    public func didFinishWithoutUpdate() {
        state = .upToDate
    }

    public func didFail(message: String) {
        state = .failed(message: message)
    }

    public func didCancel() {
        state = .idle
    }

    @discardableResult
    public func postponeRelaunch(
        hasUnsavedWork: Bool,
        hasActiveOperations: Bool,
        continuation: @escaping () -> Void
    ) -> Bool {
        let safety = Self.relaunchSafety(
            hasUnsavedWork: hasUnsavedWork,
            hasActiveOperations: hasActiveOperations
        )
        relaunchSafety = safety
        guard safety != .ready else {
            pendingRelaunch = nil
            return false
        }
        pendingRelaunch = continuation
        return true
    }

    @discardableResult
    public func resumeRelaunch(
        hasUnsavedWork: Bool,
        hasActiveOperations: Bool
    ) -> Bool {
        relaunchSafety = Self.relaunchSafety(
            hasUnsavedWork: hasUnsavedWork,
            hasActiveOperations: hasActiveOperations
        )
        guard relaunchSafety == .ready, let pendingRelaunch else { return false }
        self.pendingRelaunch = nil
        pendingRelaunch()
        return true
    }

    private static func relaunchSafety(
        hasUnsavedWork: Bool,
        hasActiveOperations: Bool
    ) -> AppUpdateRelaunchSafety {
        if hasUnsavedWork {
            .saveOrDiscardDraft
        } else if hasActiveOperations {
            .waitForActivities
        } else {
            .ready
        }
    }
}

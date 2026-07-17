import Observation
import SwiftUI

public enum AppRoute: String, CaseIterable, Codable, Sendable {
    case overview
    case containers
    case images
    case builds
    case machines
    case networks
    case volumes
    case registries
    case system
}

public enum HealthState: String, Codable, Sendable {
    case healthy
    case attention
    case unavailable
    case checking
}

@MainActor
@Observable
public final class AppState {
    public var selection: AppRoute = .overview
    public var columnVisibility: NavigationSplitViewVisibility = .all
    public var activityCenterPresented = false
    public var health: HealthState = .checking
    public let activities: ActivityCenter
    public let environment: AppEnvironment

    public init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        activities = ActivityCenter(now: environment.now, makeID: environment.makeID)
        health = environment.mode == .fakeRuntime ? .healthy : .checking
    }
}

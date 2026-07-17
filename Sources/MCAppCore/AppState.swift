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

public struct ResourceSelection: Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let kind: String

    public init(id: String, name: String, status: String, kind: String) {
        self.id = id
        self.name = name
        self.status = status
        self.kind = kind
    }
}

@MainActor
@Observable
public final class AppState {
    public var selection: AppRoute = .overview {
        didSet {
            if selection != oldValue {
                selectedResource = nil
            }
        }
    }

    public var columnVisibility: NavigationSplitViewVisibility = .all
    public var activityCenterPresented = false
    public var simpleModePresented = false
    public var health: HealthState = .checking
    public var selectedResource: ResourceSelection?
    public let activities: ActivityCenter
    public let environment: AppEnvironment

    public init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        activities = ActivityCenter(now: environment.now, makeID: environment.makeID)
        health = environment.mode == .fakeRuntime ? .healthy : .checking
    }
}

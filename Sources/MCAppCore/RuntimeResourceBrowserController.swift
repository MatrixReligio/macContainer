import Foundation
import MCContainerBridge
import MCModel
import Observation

public struct RuntimeMachineConfigurationSnapshot: Equatable, Sendable {
    public let resources: RuntimeResources
    public let homeMount: String
    public let nestedVirtualization: Bool

    public init(resources: RuntimeResources, homeMount: String, nestedVirtualization: Bool) {
        self.resources = resources
        self.homeMount = homeMount
        self.nestedVirtualization = nestedVirtualization
    }
}

public struct RuntimeResourceSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let detail: String
    public let isProtected: Bool
    public let machineConfiguration: RuntimeMachineConfigurationSnapshot?
    public let attributes: [String: String]

    public init(
        id: String,
        name: String,
        status: String,
        detail: String,
        isProtected: Bool = false,
        machineConfiguration: RuntimeMachineConfigurationSnapshot? = nil,
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.detail = detail
        self.isProtected = isProtected
        self.machineConfiguration = machineConfiguration
        self.attributes = attributes
    }
}

public protocol RuntimeResourceProviding: Sendable {
    func load(_ route: AppRoute) async throws -> [RuntimeResourceSnapshot]
    func configureMachine(id: String, request: MachineSetRequest) async throws
    func start(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult]
    func stop(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult]
    func delete(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult]
}

public struct ProductionRuntimeResourceProvider: RuntimeResourceProviding, Sendable {
    private let bridge: any RuntimeBridge

    public init(bridge: any RuntimeBridge = AppleRuntimeBridge()) {
        self.bridge = bridge
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func load(_ route: AppRoute) async throws -> [RuntimeResourceSnapshot] {
        switch route {
        case .overview:
            return []
        case .containers:
            let summaries = try await bridge.containers.list()
            var snapshots: [RuntimeResourceSnapshot] = []
            for summary in summaries {
                let detail = try await bridge.containers.inspect(id: summary.id)
                snapshots.append(.init(
                    id: summary.id,
                    name: summary.name,
                    status: Self.status(summary.state),
                    detail: summary.imageReference,
                    attributes: [
                        "Image": summary.imageReference,
                        "Networks": detail.networks.isEmpty ? "None" : detail.networks.joined(separator: ", "),
                        "Storage mounts": detail.mounts.isEmpty ? "None" : detail.mounts.map {
                            "\($0.source) → \($0.destination)"
                        }.joined(separator: ", "),
                        "CPU": String(detail.resources.cpuCount),
                        "Memory": Self.byteCount(detail.resources.memoryBytes)
                    ]
                ))
            }
            return snapshots
        case .images:
            return try await bridge.images.list().map {
                .init(
                    id: $0.reference,
                    name: $0.reference,
                    status: "Ready",
                    detail: $0.sizeBytes.map(Self.byteCount) ?? "Size unavailable"
                )
            }
        case .builds:
            let builder = try await bridge.builders.status()
            return [.init(
                id: "builder",
                name: "Apple container builder",
                status: Self.status(builder.state),
                detail: builder.resources.map(Self.resourceDescription) ?? "Default resources",
                isProtected: builder.state == .running
            )]
        case .machines:
            let summaries = try await bridge.machines.list()
            var snapshots: [RuntimeResourceSnapshot] = []
            snapshots.reserveCapacity(summaries.count)
            for summary in summaries {
                let detail = try await bridge.machines.inspect(id: summary.id)
                snapshots.append(.init(
                    id: summary.id,
                    name: summary.name,
                    status: Self.status(summary.state),
                    detail: Self.resourceDescription(summary.resources) + (summary.isDefault ? " · Default" : ""),
                    isProtected: false,
                    machineConfiguration: .init(
                        resources: summary.resources,
                        homeMount: detail.homeMount,
                        nestedVirtualization: detail.nestedVirtualization
                    ),
                    attributes: [
                        "Image": detail.imageReference ?? "System default",
                        "Home folder mount": detail.homeMount,
                        "Networks": detail.networks.isEmpty ? "Default" : detail.networks.joined(separator: ", "),
                        "Kernel": detail.kernelIdentifier ?? "Recommended",
                        "Nested virtualization": detail.nestedVirtualization ? "Enabled" : "Disabled"
                    ]
                ))
            }
            return snapshots
        case .networks:
            let summaries = try await bridge.networks.list()
            let containerDetails = try await Self.containerDetails(bridge)
            var snapshots: [RuntimeResourceSnapshot] = []
            for summary in summaries {
                let detail = try await bridge.networks.inspect(id: summary.id)
                let configuration = [detail.subnet, detail.gateway.map { "Gateway \($0)" }, detail.plugin]
                    .compactMap(\.self)
                    .joined(separator: " · ")
                snapshots.append(.init(
                    id: summary.id,
                    name: summary.name,
                    status: Self.status(summary.state),
                    detail: configuration.isEmpty ? (summary.builtIn ? "Built in" : "Custom") : configuration,
                    isProtected: summary.builtIn,
                    attributes: [
                        "Subnet": detail.subnet ?? "Runtime assigned",
                        "IPv6 subnet": detail.ipv6Subnet ?? "Runtime assigned",
                        "Gateway": detail.gateway ?? "Runtime assigned",
                        "DNS servers": detail.dnsServers.isEmpty
                            ? "Runtime default" : detail.dnsServers.joined(separator: ", "),
                        "Plugin": detail.plugin ?? "Built in",
                        "Mode": detail.mode ?? "NAT",
                        "Labels": Self.keyValues(detail.labels),
                        "Plugin options": Self.keyValues(detail.options),
                        "Used by containers": Self.containers(usingNetwork: summary.id, details: containerDetails),
                        "Editing": summary.builtIn
                            ? "Built-in network cannot be changed"
                            : "Create replacement, move workloads, then delete this network"
                    ]
                ))
            }
            return snapshots
        case .volumes:
            let summaries = try await bridge.volumes.list()
            let containerDetails = try await Self.containerDetails(bridge)
            var snapshots: [RuntimeResourceSnapshot] = []
            for summary in summaries {
                let detail = try await bridge.volumes.inspect(name: summary.name)
                snapshots.append(.init(
                    id: summary.name,
                    name: summary.name,
                    status: "Ready",
                    detail: detail.source ?? "Container persistent storage",
                    attributes: [
                        "Source": detail.source ?? "Runtime managed",
                        "Labels": detail.labels.isEmpty ? "None" : detail.labels
                            .sorted { $0.key < $1.key }
                            .map { "\($0.key)=\($0.value)" }
                            .joined(separator: ", "),
                        "Driver": detail.driver ?? "local",
                        "Capacity": detail.sizeBytes.map(Self.byteCount) ?? "Runtime default",
                        "Driver options": Self.keyValues(detail.options),
                        "Used by containers": Self.containers(usingVolume: summary.name, details: containerDetails),
                        "Attach in": "Create Container → Storage"
                    ]
                ))
            }
            return snapshots
        case .registries:
            return try await bridge.registries.list().map {
                .init(
                    id: $0.server,
                    name: $0.server,
                    status: "Connected",
                    detail: $0.username.map { "User: \($0)" } ?? "Credentials protected"
                )
            }
        case .system:
            async let summary = bridge.system.status()
            async let version = bridge.system.version()
            let (resolvedSummary, resolvedVersion) = try await (summary, version)
            return [.init(
                id: "apple-container",
                name: "Apple container service",
                status: Self.status(resolvedSummary.state),
                detail: "Runtime \(resolvedVersion.version)",
                isProtected: true
            )]
        }
    }

    // This switch is the exhaustive, typed deletion authority for every sidebar domain.
    // swiftlint:disable:next cyclomatic_complexity
    public func delete(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult] {
        guard !ids.isEmpty else { return [] }
        let results: [BatchItemResult]
        switch route {
        case .containers:
            results = try await bridge.containers.delete(ids: ids, force: false)
        case .images:
            results = try await bridge.images.delete(references: ids)
        case .machines:
            results = try await bridge.machines.delete(ids: ids, force: false)
        case .networks:
            results = try await bridge.networks.delete(ids: ids)
        case .volumes:
            results = try await bridge.volumes.delete(names: ids)
        case .registries:
            for id in ids {
                try await bridge.registries.logout(server: id)
            }
            return ids.map { .init(resourceID: $0, outcome: .succeeded) }
        case .builds:
            guard ids == ["builder"] else { throw RuntimeResourceProviderError.unsupportedDeletion }
            try await bridge.builders.delete()
            return [.init(resourceID: "builder", outcome: .succeeded)]
        case .overview, .system:
            throw RuntimeResourceProviderError.unsupportedDeletion
        }
        return results.map {
            .init(resourceID: $0.id, outcome: $0.succeeded ? .succeeded : .failed)
        }
    }

    public func start(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult] {
        let results: [BatchItemResult] = switch route {
        case .machines: try await bridge.machines.start(ids: ids)
        case .containers: try await bridge.containers.start(ids: ids)
        default: throw RuntimeResourceProviderError.unsupportedAction
        }
        return results.map(Self.activityResult)
    }

    public func configureMachine(id: String, request: MachineSetRequest) async throws {
        _ = try await bridge.machines.set(id: id, request: request)
    }

    public func stop(_ route: AppRoute, ids: [String]) async throws -> [ActivityItemResult] {
        let results: [BatchItemResult] = switch route {
        case .machines: try await bridge.machines.stop(ids: ids, force: false)
        case .containers: try await bridge.containers.stop(ids: ids, timeout: .seconds(30))
        default: throw RuntimeResourceProviderError.unsupportedAction
        }
        return results.map(Self.activityResult)
    }

    private static func activityResult(_ result: BatchItemResult) -> ActivityItemResult {
        .init(resourceID: result.id, outcome: result.succeeded ? .succeeded : .failed)
    }

    private static func status(_ state: RuntimeResourceState) -> String {
        switch state {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }

    private static func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static func resourceDescription(_ resources: RuntimeResources) -> String {
        "\(resources.cpuCount) CPU · \(byteCount(resources.memoryBytes))"
    }

    private static func keyValues(_ values: [String: String]) -> String {
        values.isEmpty ? "None" : values.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    private static func containerDetails(
        _ bridge: any RuntimeBridge
    ) async throws -> [ContainerDetail] {
        var details: [ContainerDetail] = []
        for container in try await bridge.containers.list() {
            try await details.append(bridge.containers.inspect(id: container.id))
        }
        return details
    }

    private static func containers(
        usingNetwork network: String,
        details: [ContainerDetail]
    ) -> String {
        let names = details.filter { $0.networks.contains(network) }.map(\.summary.name)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private static func containers(
        usingVolume volume: String,
        details: [ContainerDetail]
    ) -> String {
        let names = details.filter { detail in
            detail.mounts.contains { $0.source == volume }
        }.map(\.summary.name)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }
}

public enum RuntimeResourceProviderError: Error, Equatable, Sendable {
    case unsupportedDeletion
    case unsupportedAction
}

@MainActor
@Observable
public final class RuntimeResourceBrowserController {
    private var snapshots: [String: [RuntimeResourceSnapshot]] = [:]
    private var errors: [String: String] = [:]
    public private(set) var loadingRoutes = Set<String>()

    @ObservationIgnored private let provider: any RuntimeResourceProviding
    @ObservationIgnored private let activities: ActivityCenter

    public init(provider: any RuntimeResourceProviding, activities: ActivityCenter) {
        self.provider = provider
        self.activities = activities
    }

    public func resources(for route: AppRoute) -> [RuntimeResourceSnapshot] {
        snapshots[route.rawValue] ?? []
    }

    public func errorCode(for route: AppRoute) -> String? {
        errors[route.rawValue]
    }

    public func isLoading(_ route: AppRoute) -> Bool {
        loadingRoutes.contains(route.rawValue)
    }

    public func runningCount(for route: AppRoute) -> Int {
        resources(for: route).count { $0.status == "Running" }
    }

    public func totalCount(for route: AppRoute) -> Int {
        resources(for: route).count
    }

    public func refreshOverview() async {
        for route in [AppRoute.system, .containers, .machines] {
            await refresh(route)
        }
    }

    public func refresh(_ route: AppRoute) async {
        guard !loadingRoutes.contains(route.rawValue) else { return }
        loadingRoutes.insert(route.rawValue)
        defer { loadingRoutes.remove(route.rawValue) }
        let activity = activities.start(titleKey: "activity.\(route.rawValue).refresh")
        do {
            snapshots[route.rawValue] = try await provider.load(route)
            errors[route.rawValue] = nil
            activities.finish(activity, outcome: .succeeded)
        } catch is CancellationError {
            activities.finish(activity, outcome: .cancelled)
        } catch {
            errors[route.rawValue] = "resources.refresh.failed"
            activities.finish(activity, outcome: .failed)
        }
    }

    public func delete(_ route: AppRoute, ids: [String]) async {
        guard !ids.isEmpty else { return }
        let activity = activities.start(titleKey: "activity.\(route.rawValue).delete")
        do {
            let results = try await provider.delete(route, ids: ids)
            let outcome: ActivityOutcome = results.allSatisfy { $0.outcome == .succeeded }
                ? .succeeded
                : .partiallySucceeded
            activities.finish(activity, outcome: outcome, itemResults: results)
            await refresh(route)
        } catch is CancellationError {
            activities.finish(activity, outcome: .cancelled)
        } catch {
            errors[route.rawValue] = "resources.delete.failed"
            activities.finish(activity, outcome: .failed)
        }
    }

    public func start(_ route: AppRoute, ids: [String]) async {
        await perform(route, ids: ids, action: "start") {
            try await self.provider.start(route, ids: ids)
        }
    }

    public func stop(_ route: AppRoute, ids: [String]) async {
        await perform(route, ids: ids, action: "stop") {
            try await self.provider.stop(route, ids: ids)
        }
    }

    @discardableResult
    public func configureMachine(id: String, request: MachineSetRequest) async -> Bool {
        let activity = activities.start(titleKey: "activity.machines.configure")
        do {
            try await provider.configureMachine(id: id, request: request)
            errors[AppRoute.machines.rawValue] = nil
            activities.finish(
                activity,
                outcome: .succeeded,
                itemResults: [.init(resourceID: id, outcome: .succeeded)]
            )
            await refresh(.machines)
            return true
        } catch is CancellationError {
            activities.finish(activity, outcome: .cancelled)
            return false
        } catch {
            errors[AppRoute.machines.rawValue] = "resources.configure.failed"
            activities.finish(activity, outcome: .failed)
            return false
        }
    }

    private func perform(
        _ route: AppRoute,
        ids: [String],
        action: String,
        operation: () async throws -> [ActivityItemResult]
    ) async {
        guard !ids.isEmpty else { return }
        let activity = activities.start(titleKey: "activity.\(route.rawValue).\(action)")
        do {
            let results = try await operation()
            let outcome: ActivityOutcome = results.allSatisfy { $0.outcome == .succeeded }
                ? .succeeded
                : .partiallySucceeded
            activities.finish(activity, outcome: outcome, itemResults: results)
            errors[route.rawValue] = nil
            await refresh(route)
        } catch is CancellationError {
            activities.finish(activity, outcome: .cancelled)
        } catch {
            errors[route.rawValue] = "resources.\(action).failed"
            activities.finish(activity, outcome: .failed)
        }
    }
}

public actor SimulatedRuntimeResourceProvider: RuntimeResourceProviding {
    private var snapshots: [String: [RuntimeResourceSnapshot]]

    public init() {
        snapshots = [
            AppRoute.containers.rawValue: [
                .init(id: "demo-web", name: "demo-web", status: "Running", detail: "alpine:latest")
            ],
            AppRoute.images.rawValue: [
                .init(id: "alpine:latest", name: "alpine:latest", status: "Ready", detail: "8.1 MB")
            ],
            AppRoute.builds.rawValue: [
                .init(id: "builder", name: "Apple container builder", status: "Ready", detail: "Default resources")
            ],
            AppRoute.machines.rawValue: [
                .init(
                    id: "default",
                    name: "default",
                    status: "Running",
                    detail: "4 CPU · 4 GB",
                    machineConfiguration: .init(
                        resources: .init(cpuCount: 4, memoryBytes: 4_294_967_296),
                        homeMount: "none",
                        nestedVirtualization: false
                    )
                )
            ],
            AppRoute.networks.rawValue: [
                .init(id: "default", name: "default", status: "Ready", detail: "Built in", isProtected: true)
            ],
            AppRoute.volumes.rawValue: [
                .init(id: "workspace", name: "workspace", status: "Ready", detail: "Local")
            ],
            AppRoute.registries.rawValue: [
                .init(id: "ghcr.io", name: "ghcr.io", status: "Connected", detail: "Credentials protected")
            ],
            AppRoute.system.rawValue: [
                .init(
                    id: "apple-container",
                    name: "Apple container service",
                    status: "Running",
                    detail: "Runtime 1.1.0",
                    isProtected: true
                )
            ]
        ]
    }

    public func load(_ route: AppRoute) -> [RuntimeResourceSnapshot] {
        snapshots[route.rawValue] ?? []
    }

    public func delete(_ route: AppRoute, ids: [String]) -> [ActivityItemResult] {
        snapshots[route.rawValue]?.removeAll { ids.contains($0.id) }
        return ids.map { .init(resourceID: $0, outcome: .succeeded) }
    }

    public func configureMachine(id _: String, request _: MachineSetRequest) {}

    public func start(_ route: AppRoute, ids: [String]) throws -> [ActivityItemResult] {
        try updateMachineStatus(route, ids: ids, status: "Running")
    }

    public func stop(_ route: AppRoute, ids: [String]) throws -> [ActivityItemResult] {
        try updateMachineStatus(route, ids: ids, status: "Stopped")
    }

    private func updateMachineStatus(
        _ route: AppRoute,
        ids: [String],
        status: String
    ) throws -> [ActivityItemResult] {
        guard route == .machines || route == .containers else {
            throw RuntimeResourceProviderError.unsupportedAction
        }
        snapshots[route.rawValue] = snapshots[route.rawValue]?.map { snapshot in
            guard ids.contains(snapshot.id) else { return snapshot }
            return RuntimeResourceSnapshot(
                id: snapshot.id,
                name: snapshot.name,
                status: status,
                detail: snapshot.detail,
                isProtected: snapshot.isProtected,
                machineConfiguration: snapshot.machineConfiguration
            )
        }
        return ids.map { .init(resourceID: $0, outcome: .succeeded) }
    }
}

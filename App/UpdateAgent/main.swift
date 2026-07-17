import Darwin
import Foundation
import MCSystemLifecycle

if CommandLine.arguments.contains("--build-smoke-test") {
    exit(EXIT_SUCCESS)
}

let jitter = Int.random(in: UpdateAgentConfiguration.jitterRange)
Task {
    do {
        let preferences = RuntimeUpdatePreferencesStore()
        guard try preferences.load().automaticallyChecks else {
            exit(EXIT_SUCCESS)
        }
        let presenter = UpdateAgentPresenter()
        let coordinator = try ProductionUpdateCoordinatorFactory.make(
            stateSink: presenter,
            preferences: preferences
        )
        let service = UpdateAgentService(
            stateStore: PrivateUpdateAgentStateStore(),
            discovery: GitHubRuntimeReleaseDiscovery(),
            coordinator: coordinator,
            presenter: presenter
        )
        _ = try await service.check(trigger: .scheduled, jitterSeconds: TimeInterval(jitter))
        exit(EXIT_SUCCESS)
    } catch is CancellationError {
        exit(EX_TEMPFAIL)
    } catch {
        exit(EX_UNAVAILABLE)
    }
}

dispatchMain()

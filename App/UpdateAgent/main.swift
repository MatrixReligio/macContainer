import Darwin
import Foundation
import MCSystemLifecycle

if CommandLine.arguments.contains("--build-smoke-test") {
    exit(EXIT_SUCCESS)
}

let service = UpdateAgentService(
    stateStore: PrivateUpdateAgentStateStore(),
    discovery: GitHubRuntimeReleaseDiscovery(),
    coordinator: EmbeddedCatalogHandoffCoordinator(),
    presenter: UpdateAgentPresenter()
)
let jitter = Int.random(in: UpdateAgentConfiguration.jitterRange)
Task {
    do {
        _ = try await service.check(trigger: .scheduled, jitterSeconds: TimeInterval(jitter))
        exit(EXIT_SUCCESS)
    } catch is CancellationError {
        exit(EX_TEMPFAIL)
    } catch {
        exit(EX_UNAVAILABLE)
    }
}

dispatchMain()

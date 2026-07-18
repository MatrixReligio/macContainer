import MCAppCore
import MCSystemLifecycle
import SwiftUI

struct UninstallRuntimeView: View {
    private enum ResultState {
        case none
        case incomplete
        case dataPreserved
    }

    private static let confirmationToken = "REMOVE APPLE CONTAINER"

    @Environment(AppState.self) private var appState
    @State private var confirmation = ""
    @State private var result: ResultState = .none
    let isAuditMode: Bool

    init(isAuditMode: Bool = false, initialConfirmation: String = "") {
        self.isAuditMode = isAuditMode
        _confirmation = State(initialValue: initialConfirmation)
    }

    var body: some View {
        GroupBox("Remove Apple container") {
            VStack(alignment: .leading, spacing: 8) {
                inventorySummary
                    .font(.headline)

                Text("Remove runtime, preserve container data")
                    .font(.subheadline.bold())
                Text("Keeps images, volumes, configuration, and registry credentials.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Button("Remove runtime and preserve data") {
                    if isAuditMode {
                        result = .dataPreserved
                    } else {
                        Task { await runUninstall(mode: .preserveData) }
                    }
                }
                .disabled(!isAuditMode && appState.runtimeLifecycle.isBusy)
                .accessibilityIdentifier("preserve-data-uninstall")

                Divider()
                Text("Complete uninstall")
                    .font(.subheadline.bold())
                Label {
                    Text("This permanently removes runtime data, credentials, caches, and rollback points.")
                        .foregroundStyle(Color(nsColor: .labelColor))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .font(.subheadline.weight(.semibold))
                TextField("Type REMOVE APPLE CONTAINER", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("complete-uninstall-confirmation")
                Button("Completely uninstall") {
                    if isAuditMode {
                        result = .incomplete
                    } else {
                        Task { await runUninstall(mode: .complete) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(
                    confirmation != Self.confirmationToken ||
                        (!isAuditMode && appState.runtimeLifecycle.isBusy)
                )
                .accessibilityIdentifier("complete-uninstall")

                resultView

                Text("Owned artifact inventory")
                    .font(.caption.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(ResidueInventory.expectations, id: \.kind.rawValue) { item in
                        Label(item.kind.displayName, systemImage: "circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(1)
                            .accessibilityIdentifier("residue.\(item.kind.rawValue)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if isAuditMode, result == .incomplete {
            VStack(alignment: .leading, spacing: 3) {
                Label("Uninstall incomplete", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Color(nsColor: .labelColor))
                Text("Could not verify resolver cleanup")
                Text("Recovery: retry the residue audit after restoring administrator access.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
        } else if isAuditMode, result == .dataPreserved {
            Label {
                Text("Runtime removed; user data preserved")
                    .foregroundStyle(Color(nsColor: .labelColor))
            } icon: {
                Image(systemName: "externaldrive.badge.checkmark")
                    .foregroundStyle(.green)
            }
        } else if !isAuditMode {
            productionResult
        }
    }

    @ViewBuilder
    private var inventorySummary: some View {
        if isAuditMode {
            Text("Fresh inventory: 15 owned artifact categories checked")
        } else if let inventory = appState.runtimeLifecycle.preparedInventory {
            Text("Fresh inventory: \(inventory.artifactKinds.count) present of 15 owned artifact categories")
        } else {
            Text("Inventory refresh runs immediately before removal")
        }
    }

    @ViewBuilder
    private var productionResult: some View {
        switch appState.runtimeLifecycle.state {
        case let .preparingUninstall(mode):
            if mode == .complete {
                ProgressView("Refreshing complete inventory…")
            } else {
                ProgressView("Refreshing runtime inventory…")
            }
        case let .readyToUninstall(mode), let .uninstalling(mode):
            if mode == .complete {
                ProgressView("Removing and auditing all residue…")
            } else {
                ProgressView("Removing runtime…")
            }
        case let .uninstalled(completion):
            if completion == .complete {
                Label("Uninstall complete", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("No Apple container residue detected.")
                    .font(.subheadline)
            } else {
                Label("Runtime removed; user data preserved", systemImage: "externaldrive.badge.checkmark")
                    .foregroundStyle(.green)
            }
        case let .failed(code):
            VStack(alignment: .leading, spacing: 3) {
                Label("Uninstall incomplete", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(code)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("No success was recorded. Restore administrator access and retry the fresh audit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .helperApprovalRequired:
            Label("Administrator approval required", systemImage: "lock.shield")
        case .ready, .authorizingHelper, .installing, .installed:
            EmptyView()
        }
    }

    private func runUninstall(mode: UninstallMode) async {
        await appState.runtimeLifecycle.prepareUninstall(mode: mode)
        guard let inventory = appState.runtimeLifecycle.preparedInventory,
              inventory.mode == mode
        else { return }
        await appState.runtimeLifecycle.uninstall(
            mode: mode,
            inventory: inventory,
            acknowledgesIrreversibleDeletion: mode == .complete
        )
    }
}

private extension ResidueKind {
    var displayName: LocalizedStringKey {
        switch self {
        case .launchService: "Launch service"
        case .process: "Runtime process"
        case .receipt: "Installer receipt"
        case .receiptPayload: "Installed payload"
        case .applicationSupport: "Application support"
        case .configuration: "Configuration"
        case .defaultsDomain: "Preferences"
        case .registryCredential: "Registry credential"
        case .resolver: "DNS resolver"
        case .packetFilter: "Packet filter"
        case .downloadedPackage: "Downloaded package"
        case .rollbackPoint: "Rollback point"
        case .testFixture: "Test fixture"
        case .downloadCache: "Download cache"
        case .runtimeOwnedDirectory: "Runtime-owned directory"
        }
    }
}

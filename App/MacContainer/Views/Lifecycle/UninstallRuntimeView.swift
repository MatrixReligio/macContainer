import MCSystemLifecycle
import SwiftUI

struct UninstallRuntimeView: View {
    private enum ResultState {
        case none
        case incomplete
        case dataPreserved
    }

    private static let confirmationToken = "REMOVE APPLE CONTAINER"

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
                Text("Fresh inventory: 15 owned artifact categories checked")
                    .font(.headline)

                Text("Remove runtime, preserve container data")
                    .font(.subheadline.bold())
                Text("Keeps images, volumes, configuration, and registry credentials.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Button("Remove runtime and preserve data") {
                    result = .dataPreserved
                }
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
                    result = isAuditMode ? .incomplete : .none
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(confirmation != Self.confirmationToken)
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
        if result == .incomplete {
            VStack(alignment: .leading, spacing: 3) {
                Label("Uninstall incomplete", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(Color(nsColor: .labelColor))
                Text("Could not verify resolver cleanup")
                Text("Recovery: retry the residue audit after restoring administrator access.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
        } else if result == .dataPreserved {
            Label {
                Text("Runtime removed; user data preserved")
                    .foregroundStyle(Color(nsColor: .labelColor))
            } icon: {
                Image(systemName: "externaldrive.badge.checkmark")
                    .foregroundStyle(.green)
            }
        }
    }
}

private extension ResidueKind {
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}

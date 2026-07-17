import MCContracts
import MCModel
import SwiftUI

struct OperationReview: View {
    let operation: OperationContract
    let draft: OperationDraft
    let runtimeVersion: RuntimeVersion
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Operation") {
                    LabeledContent("Action", value: operation.id)
                    LabeledContent("Runtime", value: runtimeVersion.description)
                    LabeledContent("Risk", value: operation.risk.rawValue.capitalized)
                }
                Section("Effective values") {
                    ForEach(operation.parameters) { parameter in
                        if let field = draft.fields[parameter.id], field.value != .none {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(LocalizedStringKey(parameter.labelKey))
                                    Spacer()
                                    Text(field.value.displayValue)
                                        .font(.body.monospaced())
                                        .privacySensitive(field.value.containsSecret)
                                }
                                Text(field.source.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Safety") {
                    Label(
                        "Uses the typed runtime bridge; no shell command is generated.",
                        systemImage: "checkmark.shield"
                    )
                    Label(
                        "Activity Center records progress and item-level outcomes.",
                        systemImage: "list.bullet.rectangle"
                    )
                }
            }
            .navigationTitle("Review \(operation.id)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") { isPresented = false }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .accessibilityIdentifier("run-operation.\(operation.id)")
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .accessibilityIdentifier("operation-review.\(operation.id)")
    }
}

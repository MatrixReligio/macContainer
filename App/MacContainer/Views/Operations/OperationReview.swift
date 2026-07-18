import MCAppCore
import MCContracts
import MCModel
import SwiftUI

struct OperationReview: View {
    @Environment(AppState.self) private var state

    let operation: OperationContract
    let draft: OperationDraft
    let runtimeVersion: RuntimeVersion
    @Binding var isPresented: Bool
    @State private var isRunning = false
    @State private var resultSummary: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Operation") {
                    LabeledContent("Action", value: operation.id)
                    LabeledContent("Runtime", value: runtimeVersion.description)
                    LabeledContent("Risk") {
                        Text(operation.risk.localizedTitle)
                    }
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
                                Text(field.source.localizedTitle)
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
                if isRunning || resultSummary != nil || errorMessage != nil {
                    Section("Result") {
                        if isRunning {
                            HStack {
                                ProgressView()
                                Text("Running through the native runtime bridge…")
                            }
                        } else if let resultSummary {
                            Label(resultSummary, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .textSelection(.enabled)
                        } else if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Review \(operation.id)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(resultSummary == nil ? (errorMessage == nil ? "Run" : "Retry") : "Done") {
                        if resultSummary != nil {
                            isPresented = false
                        } else {
                            run()
                        }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isRunning)
                    .accessibilityIdentifier("run-operation.\(operation.id)")
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .accessibilityIdentifier("operation-review.\(operation.id)")
    }

    private func run() {
        isRunning = true
        resultSummary = nil
        errorMessage = nil
        Task {
            do {
                let result = try await state.executeOperation(draft)
                resultSummary = result.summary
            } catch {
                errorMessage = ErrorMapper().map(
                    error,
                    domain: .unknown,
                    operationID: operation.id
                ).diagnosticDetail
            }
            isRunning = false
        }
    }
}

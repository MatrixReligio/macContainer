import MCContracts
import MCModel
import MCTemplates
import SwiftUI

struct TemplateReviewView: View {
    let template: ScenarioTemplate
    let review: TemplateReview
    let contract: UpstreamContract
    @Binding var isPresented: Bool
    let onRun: () -> Void

    @State private var advancedEditorPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Outcome") {
                    LabeledContent("Template") {
                        Text(template.id)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(nsColor: .labelColor))
                    }
                    LabeledContent("Native operation") {
                        Text(review.draft.operationID)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(nsColor: .labelColor))
                    }
                    Text("Every generated value, its source, and its difference from Apple defaults is shown below.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                }

                Section("Generated values") {
                    ForEach(review.rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(row.parameterID)
                                    .font(.title3.monospaced().weight(.bold))
                                    .foregroundStyle(Color(nsColor: .labelColor))
                                Spacer()
                                Text(row.value.displayValue)
                                    .textSelection(.enabled)
                                    .privacySensitive(row.value.containsSecret)
                            }
                            HStack {
                                Text(row.sourceDescriptionKey)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(nsColor: .labelColor))
                                Spacer()
                                if review.diffFromUpstream.contains(where: { $0.id == row.id }) {
                                    Label {
                                        Text("Changed from Apple default")
                                            .foregroundStyle(Color(nsColor: .labelColor))
                                    } icon: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundStyle(.blue)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .accessibilityIdentifier("template-review-row.\(row.parameterID)")
                    }
                }

                Section("Control") {
                    Button("Edit all parameters") {
                        advancedEditorPresented = true
                    }
                    .accessibilityIdentifier("template-review.edit-all")
                }
            }
            .navigationTitle("Review \(template.id)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") {
                        onRun()
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("template-run")
                }
            }
        }
        .frame(minWidth: 720, minHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("template-review.\(template.id)")
        .sheet(isPresented: $advancedEditorPresented) {
            if let operation = contract.operation(id: review.draft.operationID) {
                OperationForm(
                    operation: operation,
                    runtimeVersion: contract.runtimeVersion,
                    draft: review.draft
                )
                .frame(minWidth: 900, minHeight: 650)
            }
        }
    }
}

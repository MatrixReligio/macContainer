import MCAppCore
import MCContracts
import MCModel
import SwiftUI

struct OperationForm: View {
    let operation: OperationContract
    let runtimeVersion: RuntimeVersion

    @State private var draft: OperationDraft
    @State private var reviewPresented = false

    init(operation: OperationContract, runtimeVersion: RuntimeVersion) {
        self.operation = operation
        self.runtimeVersion = runtimeVersion
        _draft = State(initialValue: OperationDraftFactory().makeDraft(for: operation))
    }

    private var issues: [ValidationIssue] {
        OperationValidator().validate(draft, against: operation)
    }

    private var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if operation.risk == .destructive || operation.risk == .privileged {
                        riskBanner
                    }

                    ForEach(operation.parameters) { parameter in
                        ParameterField(
                            operation: operation,
                            parameter: parameter,
                            field: fieldBinding(for: parameter)
                        )
                    }

                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.messageKey, systemImage: "exclamationmark.circle")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .accessibilityIdentifier("validation.\(operation.id).\(issue.parameterID)")
                    }
                }
                .padding(20)
                .frame(maxWidth: 780, alignment: .leading)
            }
            .accessibilityIdentifier("operation-form-scroll")

            Divider()
            HStack {
                Text(hasErrors ? "Resolve validation issues before review." : "Ready to review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Review") {
                    reviewPresented = true
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(hasErrors)
                .accessibilityIdentifier("review-operation.\(operation.id)")
            }
            .padding(14)
        }
        .navigationTitle(operation.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("operation-form.\(operation.id)")
        .sheet(isPresented: $reviewPresented) {
            OperationReview(
                operation: operation,
                draft: draft,
                runtimeVersion: runtimeVersion,
                isPresented: $reviewPresented
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(operation.id)
                    .font(.title2.weight(.semibold).monospaced())
                Text(verbatim: "Native \(operation.nativeAction) · Apple container \(runtimeVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(operation.risk.rawValue.capitalized)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
                .foregroundStyle(tint)
        }
        .padding(16)
    }

    private var riskBanner: some View {
        Label {
            Text(operation.risk == .privileged
                ? "This action changes system-managed runtime state and may require administrator approval."
                : "This action can permanently remove runtime resources. Review every affected item before running.")
        } icon: {
            Image(systemName: "exclamationmark.shield.fill")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("operation-risk.\(operation.id)")
    }

    private func fieldBinding(for parameter: ParameterContract) -> Binding<DraftField> {
        Binding(
            get: { draft.fields[parameter.id] ?? DraftField(value: .none, source: .userOverride) },
            set: { draft.fields[parameter.id] = $0 }
        )
    }

    private var symbol: String {
        switch operation.risk {
        case .readOnly: "eye"
        case .mutating: "slider.horizontal.3"
        case .destructive: "trash"
        case .privileged: "lock.shield"
        }
    }

    private var tint: Color {
        switch operation.risk {
        case .readOnly: .blue
        case .mutating: .accentColor
        case .destructive, .privileged: .orange
        }
    }
}

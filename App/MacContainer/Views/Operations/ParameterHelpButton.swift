import MCContracts
import SwiftUI

struct ParameterHelpButton: View {
    let operation: OperationContract
    let parameter: ParameterContract

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(parameter.conciseHelpKey)
        .accessibilityLabel("Information about \(parameter.labelKey)")
        .accessibilityIdentifier("parameter-help.\(operation.id).\(parameter.id)")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.tint)
                    Text(parameter.labelKey)
                        .font(.headline)
                    Spacer()
                    Text(parameter.valueType.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
                Text(parameter.detailedHelpKey)
                    .fixedSize(horizontal: false, vertical: true)
                if parameter.acceptedValues.isEmpty == false {
                    LabeledContent("Accepted values", value: parameter.acceptedValues.joined(separator: ", "))
                }
                if let grammar = parameter.grammar {
                    LabeledContent("Validation", value: grammar)
                        .font(.caption)
                }
                LabeledContent("Required", value: parameter.required ? "Yes" : "No")
                LabeledContent("Security impact", value: parameter.securityImpact.rawValue.capitalized)
                Text(parameter.recoveryKey)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding(18)
            .frame(width: 430)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Information about \(parameter.labelKey)")
            .accessibilityIdentifier("parameter-help-popover")
        }
    }
}

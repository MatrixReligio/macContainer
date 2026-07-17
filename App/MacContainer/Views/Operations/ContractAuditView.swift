import AppKit
import MCContracts
import SwiftUI

struct ContractAuditView: View {
    let contract: UpstreamContract

    @State private var searchText = ""
    @State private var selection: String?

    private var filteredOperations: [OperationContract] {
        guard searchText.isEmpty == false else { return contract.operations }
        return contract.operations.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.domain.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Operation catalog")
                        .font(.headline)
                    Text("\(contract.operations.count) operations · \(parameterCount) parameters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    OperationSearchField(text: $searchText)
                        .frame(height: 28)
                }
                .padding(12)

                Divider()

                List(filteredOperations) { operation in
                    Button {
                        selection = operation.id
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(operation.id)
                                .font(.body.monospaced())
                            Text(operation.domain.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-operation.\(operation.id)")
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            if let operation = selectedOperation {
                OperationForm(operation: operation, runtimeVersion: contract.runtimeVersion)
                    .id(operation.id)
            } else {
                ContentUnavailableView(
                    "Choose an operation",
                    systemImage: "slider.horizontal.3",
                    description: Text("Search the complete Apple container contract to configure a native action.")
                )
            }
        }
        .navigationTitle("Contract audit")
        .accessibilityIdentifier("contract-audit")
        .onChange(of: searchText) {
            if filteredOperations.count == 1 {
                selection = filteredOperations[0].id
            }
        }
    }

    private var parameterCount: Int {
        contract.operations.reduce(0) { $0 + $1.parameters.count }
    }

    private var selectedOperation: OperationContract? {
        selection.flatMap(contract.operation(id:))
    }
}

private struct OperationSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search 61 operations"
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.sendsSearchStringImmediately = true
        field.setAccessibilityIdentifier("operation-search")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.setAccessibilityIdentifier("operation-search")
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc
        func changed(_ sender: NSSearchField) {
            text = sender.stringValue
        }
    }
}

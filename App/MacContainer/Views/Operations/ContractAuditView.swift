import MCContracts
import SwiftUI

struct ContractAuditView: View {
    let contract: UpstreamContract

    @State private var searchText = ""
    @State private var selection: String?

    init(contract: UpstreamContract, initialSelection: String? = nil) {
        self.contract = contract
        _selection = State(initialValue: initialSelection)
    }

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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
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
                            Text(operation.domain.localizedTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(humanReadableLabel(for: operation))
                    .accessibilityHint("Operation ID \(operation.id)")
                    .accessibilityIdentifier("open-operation.\(operation.id)")
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            if let operation = selectedOperation {
                OperationForm(operation: operation, runtimeVersion: contract.runtimeVersion)
                    .id(operation.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text("Choose an operation")
                        .font(.title2.bold())
                    Text("Search the complete Apple container contract to configure a native action.")
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.primary)
                .padding(24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Choose an operation. Search the complete Apple container contract to configure a native action."
                )
            }
        }
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

    private func humanReadableLabel(for operation: OperationContract) -> String {
        let action = operation.id
            .split(separator: ".")
            .dropFirst()
            .joined(separator: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
        return "\(String(localized: "Configure native operation")): \(action)"
    }
}

private struct OperationSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search 61 operations", text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search operations")
                .accessibilityIdentifier("operation-search")
            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear operation search")
                .accessibilityIdentifier("operation-search-clear")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
    }
}

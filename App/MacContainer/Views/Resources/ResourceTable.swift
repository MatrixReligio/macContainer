import AppKit
import MCAppCore
import MCModel
import SwiftUI

struct ResourceRow: Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let detail: String
    let isProtected: Bool
}

struct ResourceTable: View {
    @Environment(AppState.self) private var state
    let route: AppRoute
    let resources: [ResourceRow]

    @State private var searchText = ""
    @State private var selection: Set<ResourceRow.ID> = []
    @State private var confirmationPresented = false

    private var filteredResources: [ResourceRow] {
        guard searchText.isEmpty == false else { return resources }
        return resources.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.status.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedRows: [ResourceRow] {
        resources.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                NativeSearchField(
                    text: $searchText,
                    prompt: "Search \(route.title.lowercased())",
                    identifier: "resource-search.\(route.rawValue)"
                )
                .frame(maxWidth: 320)

                Spacer()

                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("refresh-resources.\(route.rawValue)")

                Button {
                    confirmationPresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedRows.isEmpty || selectedRows.contains(where: \.isProtected))
                .accessibilityIdentifier("delete-selected.\(route.rawValue)")
            }
            .padding(12)

            Divider()

            if filteredResources.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No Results",
                    message: "Try a different search."
                )
            } else {
                Table(filteredResources, selection: $selection) {
                    TableColumn("Name") { resource in
                        Text(resource.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(nsColor: .labelColor))
                    }
                    TableColumn("Status", value: \.status)
                    TableColumn("Details", value: \.detail)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("\(route.title) resources")
                .accessibilityIdentifier("resource-table.\(route.rawValue)")
                .contextMenu(forSelectionType: ResourceRow.ID.self) { selectedIDs in
                    if let resource = resources.first(where: { selectedIDs.contains($0.id) }) {
                        Button("Inspect") {
                            selection = selectedIDs
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            selection = selectedIDs
                            confirmationPresented = true
                        }
                        .disabled(resource.isProtected)
                    }
                }
                .onChange(of: selection) {
                    guard let id = selection.first,
                          let resource = resources.first(where: { $0.id == id })
                    else {
                        state.selectedResource = nil
                        return
                    }
                    state.selectedResource = ResourceSelection(
                        id: resource.id,
                        name: resource.name,
                        status: resource.status,
                        kind: route.singularTitle
                    )
                }
            }
        }
        .navigationTitle(route.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(route.rawValue)-content")
        .sheet(isPresented: $confirmationPresented) {
            DestructiveConfirmation(
                resourceKind: route.singularTitle,
                resourceIDs: selectedRows.map(\.id),
                isPresented: $confirmationPresented
            ) {
                deleteSelectedRows()
            }
        }
    }

    private func refresh() {
        let id = state.activities.start(titleKey: "activity.\(route.rawValue).refresh")
        state.activities.finish(id, outcome: .succeeded)
    }

    private func deleteSelectedRows() {
        let ids = selectedRows.map(\.id)
        let id = state.activities.start(titleKey: "activity.\(route.rawValue).delete")
        state.activities.finish(
            id,
            outcome: .succeeded,
            itemResults: ids.map { ActivityItemResult(resourceID: $0, outcome: .succeeded) }
        )
        selection = []
    }
}

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let identifier: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.sendsSearchStringImmediately = true
        field.setAccessibilityIdentifier(identifier)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = prompt
        field.setAccessibilityIdentifier(identifier)
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

import AppKit
import MCAppCore
import MCModel
import SwiftUI

struct ResourceTable: View {
    @Environment(AppState.self) private var state
    let route: AppRoute
    let resources: [RuntimeResourceSnapshot]

    @State private var searchText = ""
    @State private var selection: Set<RuntimeResourceSnapshot.ID> = []
    @State private var confirmationPresented = false

    private var filteredResources: [RuntimeResourceSnapshot] {
        guard searchText.isEmpty == false else { return resources }
        return resources.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.status.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedRows: [RuntimeResourceSnapshot] {
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
                if let error = state.resourceBrowser.errorCode(for: route) {
                    EmptyStateView(
                        symbol: "exclamationmark.triangle",
                        title: "Resources unavailable",
                        message: error
                    )
                    .accessibilityIdentifier("resource-error.\(route.rawValue)")
                } else {
                    EmptyStateView(
                        symbol: searchText.isEmpty ? "shippingbox" : "magnifyingglass",
                        title: searchText.isEmpty ? "No resources" : "No Results",
                        message: searchText.isEmpty
                            ? "Create a resource or refresh after the runtime starts."
                            : "Try a different search."
                    )
                    .accessibilityIdentifier("resource-empty.\(route.rawValue)")
                }
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
                .contextMenu(forSelectionType: RuntimeResourceSnapshot.ID.self) { selectedIDs in
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
        Task { await state.resourceBrowser.refresh(route) }
    }

    private func deleteSelectedRows() {
        let ids = selectedRows.map(\.id)
        selection = []
        Task { await state.resourceBrowser.delete(route, ids: ids) }
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

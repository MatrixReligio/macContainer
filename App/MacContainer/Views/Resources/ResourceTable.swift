import AppKit
import MCAppCore
import MCContracts
import MCModel
import SwiftUI

struct ResourceTable: View {
    @Environment(AppState.self) private var state
    let route: AppRoute
    let resources: [RuntimeResourceSnapshot]

    @State private var searchText = ""
    @State private var selection: Set<RuntimeResourceSnapshot.ID> = []
    @State private var confirmationPresented = false
    @State private var machineConfigurationPresented = false
    @State private var registryLoginPresented = false

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
                    prompt: route.searchPrompt,
                    identifier: "resource-search.\(route.rawValue)"
                )
                .frame(maxWidth: 320)

                Spacer()

                if route == .machines {
                    machineActions
                }

                if route == .registries {
                    Button {
                        registryLoginPresented = true
                    } label: {
                        Label("Log In", systemImage: "person.badge.key")
                    }
                    .accessibilityIdentifier("login-registry")
                }

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
                        message: "Refresh after the runtime is available.",
                        diagnostic: error
                    )
                    .accessibilityIdentifier("resource-error.\(route.rawValue)")
                } else {
                    EmptyStateView(
                        symbol: searchText.isEmpty ? "shippingbox" : "magnifyingglass",
                        title: emptyTitle,
                        message: searchText.isEmpty
                            ? emptyMessage
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
                    TableColumn("Status") { resource in
                        Text(LocalizedStringKey(resource.status))
                    }
                    TableColumn("Details") { resource in
                        Text(verbatim: resource.detail)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("Resource table")
                .accessibilityIdentifier("resource-table.\(route.rawValue)")
                .contextMenu(forSelectionType: RuntimeResourceSnapshot.ID.self) { selectedIDs in
                    if let resource = resources.first(where: { selectedIDs.contains($0.id) }) {
                        Button("Inspect") {
                            selection = selectedIDs
                        }
                        if route == .machines {
                            Button("Configure") {
                                selection = selectedIDs
                                machineConfigurationPresented = true
                            }
                            .disabled(resource.machineConfiguration == nil)
                            Button("Start") {
                                selection = selectedIDs
                                startSelectedMachines()
                            }
                            .disabled(resource.status == "Running" || resource.status == "Starting")
                            Button("Stop") {
                                selection = selectedIDs
                                stopSelectedMachines()
                            }
                            .disabled(resource.status == "Stopped" || resource.status == "Stopping")
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
        .navigationTitle(LocalizedStringKey(route.title))
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
        .sheet(isPresented: $machineConfigurationPresented) {
            if let machine = selectedRows.first, let configuration = machine.machineConfiguration {
                MachineConfigurationSheet(
                    machine: machine,
                    configuration: configuration,
                    isPresented: $machineConfigurationPresented
                )
            }
        }
        .sheet(isPresented: $registryLoginPresented) {
            if let operation = Self.contract?.operation(id: "registries.login") {
                DismissibleOperationSheet(
                    operation: operation,
                    runtimeVersion: .init(major: 1, minor: 1, patch: 0),
                    draft: OperationDraftFactory().makeDraft(for: operation),
                    isPresented: $registryLoginPresented
                )
            }
        }
    }

    private var emptyTitle: LocalizedStringKey {
        guard searchText.isEmpty else { return "No Results" }
        return route == .registries ? "No registry credentials" : "No resources"
    }

    private var emptyMessage: LocalizedStringKey {
        if route == .registries {
            return "Log in to a registry to store a reviewed credential, then refresh this list."
        }
        return "Create a resource or refresh after the runtime starts."
    }

    private static let contract = try? ContractRepository.bundled(
        version: RuntimeVersion(major: 1, minor: 1, patch: 0)
    )

    private var machineActions: some View {
        ViewThatFits(in: .horizontal) {
            machineActionButtons(compact: false)
                .fixedSize()
            machineActionButtons(compact: true)
        }
    }

    @ViewBuilder
    private func machineActionButtons(compact: Bool) -> some View {
        if compact {
            machineButtons
                .labelStyle(.iconOnly)
        } else {
            machineButtons
                .labelStyle(.titleAndIcon)
        }
    }

    private var machineButtons: some View {
        HStack(spacing: 8) {
            Button {
                state.simpleModeInitialTemplateID = "linux-machine-workspace"
                state.simpleModePresented = true
            } label: {
                Label("New Machine", systemImage: "plus")
            }
            .accessibilityIdentifier("new-machine")
            .help("New Machine")

            Button {
                machineConfigurationPresented = true
            } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
            }
            .disabled(selectedRows.count != 1 || selectedRows.first?.machineConfiguration == nil)
            .accessibilityIdentifier("configure-machine")
            .help("Configure")

            Button {
                startSelectedMachines()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(selectedRows.isEmpty || selectedRows.allSatisfy {
                $0.status == "Running" || $0.status == "Starting"
            })
            .accessibilityIdentifier("start-machine")
            .help("Start")

            Button {
                stopSelectedMachines()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(selectedRows.isEmpty || selectedRows.allSatisfy {
                $0.status == "Stopped" || $0.status == "Stopping"
            })
            .accessibilityIdentifier("stop-machine")
            .help("Stop")
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

    private func startSelectedMachines() {
        let ids = selectedRows
            .filter { $0.status != "Running" && $0.status != "Starting" }
            .map(\.id)
        guard ids.isEmpty == false else { return }
        Task { await state.resourceBrowser.start(.machines, ids: ids) }
    }

    private func stopSelectedMachines() {
        let ids = selectedRows
            .filter { $0.status != "Stopped" && $0.status != "Stopping" }
            .map(\.id)
        guard ids.isEmpty == false else { return }
        Task { await state.resourceBrowser.stop(.machines, ids: ids) }
    }
}

private struct MachineConfigurationSheet: View {
    @Environment(AppState.self) private var state

    let machine: RuntimeResourceSnapshot
    @Binding var isPresented: Bool

    @State private var cpuCount: Int
    @State private var memoryGiB: Int
    @State private var sharesHomeReadOnly: Bool
    @State private var nestedVirtualization: Bool
    @State private var isSaving = false
    @State private var errorCode: String?

    init(
        machine: RuntimeResourceSnapshot,
        configuration: RuntimeMachineConfigurationSnapshot,
        isPresented: Binding<Bool>
    ) {
        self.machine = machine
        _isPresented = isPresented
        _cpuCount = State(initialValue: configuration.resources.cpuCount)
        _memoryGiB = State(initialValue: max(1, Int(configuration.resources.memoryBytes / 1_073_741_824)))
        _sharesHomeReadOnly = State(initialValue: configuration.homeMount != "none")
        _nestedVirtualization = State(initialValue: configuration.nestedVirtualization)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Resources") {
                    Stepper(value: $cpuCount, in: 1 ... max(1, ProcessInfo.processInfo.activeProcessorCount)) {
                        LabeledContent("CPU cores", value: String(cpuCount))
                    }
                    Stepper(value: $memoryGiB, in: 1 ... maximumMemoryGiB) {
                        LabeledContent("Memory", value: "\(memoryGiB) GiB")
                    }
                }

                Section("Capabilities") {
                    Toggle("Share home folder read-only", isOn: $sharesHomeReadOnly)
                    Toggle("Enable nested virtualization", isOn: $nestedVirtualization)
                    Text("Home sharing uses a one-time consent and is never enabled implicitly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorCode {
                    Section("Recovery") {
                        Text(verbatim: errorCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Configure \(machine.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 430)
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("machine-configuration")
    }

    private var maximumMemoryGiB: Int {
        max(1, Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
    }

    private func save() {
        isSaving = true
        errorCode = nil
        let request = MachineSetRequest(
            resources: .init(
                cpuCount: cpuCount,
                memoryBytes: Int64(memoryGiB) * 1_073_741_824
            ),
            homeMount: sharesHomeReadOnly ? "ro" : "none",
            homeSharingConsent: sharesHomeReadOnly ? HomeSharingConsent(token: UUID()) : nil,
            nestedVirtualization: nestedVirtualization
        )
        Task {
            let saved = await state.resourceBrowser.configureMachine(id: machine.id, request: request)
            isSaving = false
            if saved {
                isPresented = false
            } else {
                errorCode = "resources.configure.failed"
            }
        }
    }
}

private extension AppRoute {
    var searchPrompt: String {
        switch self {
        case .overview: String(localized: "Search resources")
        case .containers: String(localized: "Search containers")
        case .images: String(localized: "Search images")
        case .builds: String(localized: "Search builds")
        case .machines: String(localized: "Search machines")
        case .networks: String(localized: "Search networks")
        case .volumes: String(localized: "Search volumes")
        case .registries: String(localized: "Search registries")
        case .system: String(localized: "Search system resources")
        }
    }
}

struct DismissibleOperationSheet: View {
    let operation: OperationContract
    let runtimeVersion: RuntimeVersion
    let draft: OperationDraft
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            OperationForm(operation: operation, runtimeVersion: runtimeVersion, draft: draft)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isPresented = false
                        }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("close-operation-form")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 650)
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

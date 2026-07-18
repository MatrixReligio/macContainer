import AppKit
import MCAppCore
import MCContracts
import MCModel
import SwiftUI

// swiftlint:disable type_body_length
struct ResourceTable: View {
    @Environment(AppState.self) private var state
    let route: AppRoute
    let resources: [RuntimeResourceSnapshot]

    @State private var searchText = ""
    @State private var selection: Set<RuntimeResourceSnapshot.ID> = []
    @State private var confirmationPresented = false
    @State private var machineConfigurationPresented = false
    @State private var registryLoginPresented = false
    @State private var networkCreatePresented = false
    @State private var networkCreateDraft: OperationDraft?
    @State private var volumeCreatePresented = false
    @State private var imagePullPresented = false
    @State private var buildCreatePresented = false
    @State private var machineTerminal: MachineTerminalPresentation?
    @State private var machineTerminalOpening = false
    @State private var machineTerminalErrorPresented = false

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

                if route == .containers {
                    Button {
                        state.creationIntent = .container
                        state.simpleModeInitialTemplateID = "quick-run"
                        state.simpleModePresented = true
                    } label: {
                        Label("New Container", systemImage: "plus")
                    }
                    .accessibilityIdentifier("new-container")
                    Button {
                        openSelectedContainerTerminal()
                    } label: {
                        Label("Open Terminal", systemImage: "terminal")
                    }
                    .disabled(
                        selectedRows.count != 1 || selectedRows.first?.status != "Running" || machineTerminalOpening
                    )
                    Button {
                        startSelectedResources()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(selectedRows.isEmpty || selectedRows.allSatisfy {
                        $0.status == "Running" || $0.status == "Starting"
                    })
                    Button {
                        stopSelectedResources()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(selectedRows.isEmpty || selectedRows.allSatisfy {
                        $0.status == "Stopped" || $0.status == "Stopping"
                    })
                }

                if route == .images {
                    Button {
                        imagePullPresented = true
                    } label: {
                        Label("Pull Image", systemImage: "arrow.down.circle")
                    }
                    .accessibilityIdentifier("pull-image")
                }

                if route == .builds {
                    Button {
                        buildCreatePresented = true
                    } label: {
                        Label("New Build", systemImage: "hammer")
                    }
                    .accessibilityIdentifier("new-build")
                }

                if route == .networks {
                    Button {
                        presentNewNetwork()
                    } label: {
                        Label("New Network", systemImage: "plus")
                    }
                    .accessibilityIdentifier("new-network")
                    Button {
                        presentNetworkReplacement()
                    } label: {
                        Label("Create Replacement", systemImage: "plus.square.on.square")
                    }
                    .disabled(selectedRows.count != 1 || selectedRows.first?.isProtected == true)
                    .help("Networks cannot be edited in place. Create a replacement, then move workloads.")
                }

                if route == .volumes {
                    Button {
                        volumeCreatePresented = true
                    } label: {
                        Label("New Volume", systemImage: "plus")
                    }
                    .accessibilityIdentifier("new-volume")
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
                            Button("Open Terminal") {
                                selection = selectedIDs
                                openSelectedMachineTerminal()
                            }
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
                        if route == .containers {
                            Button("Open Terminal") {
                                selection = selectedIDs
                                openSelectedContainerTerminal()
                            }
                            .disabled(resource.status != "Running")
                            Button("Start") {
                                selection = selectedIDs
                                startSelectedResources()
                            }
                            .disabled(resource.status == "Running" || resource.status == "Starting")
                            Button("Stop") {
                                selection = selectedIDs
                                stopSelectedResources()
                            }
                            .disabled(resource.status == "Stopped" || resource.status == "Stopping")
                        }
                        if route == .networks, resource.isProtected == false {
                            Button("Create Replacement…") {
                                selection = selectedIDs
                                presentNetworkReplacement()
                            }
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
                        kind: route.singularTitle,
                        detail: resource.detail,
                        attributes: resource.attributes
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
        .sheet(isPresented: $networkCreatePresented) {
            if let operation = Self.contract?.operation(id: "networks.create"), let draft = networkCreateDraft {
                DismissibleOperationSheet(
                    operation: operation,
                    runtimeVersion: .init(major: 1, minor: 1, patch: 0),
                    draft: draft,
                    isPresented: $networkCreatePresented
                )
            }
        }
        .sheet(isPresented: $volumeCreatePresented) {
            operationSheet(id: "volumes.create", isPresented: $volumeCreatePresented)
        }
        .sheet(isPresented: $imagePullPresented) {
            operationSheet(id: "images.pull", isPresented: $imagePullPresented)
        }
        .sheet(isPresented: $buildCreatePresented) {
            operationSheet(id: "core.build", isPresented: $buildCreatePresented)
        }
        .sheet(item: $machineTerminal) { presentation in
            TerminalSessionView(
                controller: presentation.controller,
                title: presentation.title
            )
        }
        .alert("Unable to open terminal", isPresented: $machineTerminalErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected resource could not be started or its interactive shell could not be opened.")
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
        if route == .volumes {
            return "Create a named volume, then attach it to a container in the workload wizard."
        }
        if route == .networks {
            return "Create a network, then select it while configuring a container workload."
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
                state.creationIntent = .machine
                state.simpleModePresented = true
            } label: {
                Label("New Machine", systemImage: "plus")
            }
            .accessibilityIdentifier("new-machine")
            .help("New Machine")

            Button {
                openSelectedMachineTerminal()
            } label: {
                if machineTerminalOpening {
                    ProgressView()
                } else {
                    Label("Open Terminal", systemImage: "terminal")
                }
            }
            .disabled(selectedRows.count != 1 || machineTerminalOpening)
            .accessibilityIdentifier("open-machine-terminal")
            .help("Open Terminal")

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

    private func presentNewNetwork() {
        guard let operation = Self.contract?.operation(id: "networks.create") else { return }
        networkCreateDraft = OperationDraftFactory().makeDraft(for: operation)
        networkCreatePresented = true
    }

    private func presentNetworkReplacement() {
        guard let source = selectedRows.first,
              selectedRows.count == 1,
              source.isProtected == false,
              let operation = Self.contract?.operation(id: "networks.create")
        else { return }
        var draft = OperationDraftFactory().makeDraft(for: operation)
        draft.fields["name"] = .init(value: .string("\(source.name)-replacement"), source: .userOverride)
        let hostOnly = source.attributes["Mode"]?.localizedCaseInsensitiveContains("host") == true
        draft.fields["internal"] = .init(value: .bool(hostOnly), source: .userOverride)
        if let plugin = source.attributes["Plugin"], plugin != "Built in" {
            draft.fields["plugin"] = .init(value: .string(plugin), source: .userOverride)
        }
        networkCreateDraft = draft
        networkCreatePresented = true
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

    private func startSelectedResources() {
        let ids = selectedRows
            .filter { $0.status != "Running" && $0.status != "Starting" }
            .map(\.id)
        guard ids.isEmpty == false else { return }
        Task { await state.resourceBrowser.start(route, ids: ids) }
    }

    private func stopSelectedResources() {
        let ids = selectedRows
            .filter { $0.status != "Stopped" && $0.status != "Stopping" }
            .map(\.id)
        guard ids.isEmpty == false else { return }
        Task { await state.resourceBrowser.stop(route, ids: ids) }
    }

    private func stopSelectedMachines() {
        let ids = selectedRows
            .filter { $0.status != "Stopped" && $0.status != "Stopping" }
            .map(\.id)
        guard ids.isEmpty == false else { return }
        Task { await state.resourceBrowser.stop(.machines, ids: ids) }
    }

    @ViewBuilder
    private func operationSheet(id: String, isPresented: Binding<Bool>) -> some View {
        if let operation = Self.contract?.operation(id: id) {
            DismissibleOperationSheet(
                operation: operation,
                runtimeVersion: .init(major: 1, minor: 1, patch: 0),
                draft: OperationDraftFactory().makeDraft(for: operation),
                isPresented: isPresented
            )
        }
    }

    private func openSelectedMachineTerminal() {
        guard let machine = selectedRows.first, selectedRows.count == 1 else { return }
        machineTerminalOpening = true
        Task {
            do {
                let controller = try await state.openMachineTerminal(machineID: machine.id)
                machineTerminal = MachineTerminalPresentation(
                    controller: controller,
                    title: "Virtual machine terminal"
                )
            } catch {
                machineTerminalErrorPresented = true
            }
            machineTerminalOpening = false
        }
    }

    private func openSelectedContainerTerminal() {
        guard let container = selectedRows.first,
              selectedRows.count == 1,
              container.status == "Running"
        else { return }
        machineTerminalOpening = true
        Task {
            do {
                let controller = try await state.openContainerTerminal(containerID: container.id)
                machineTerminal = MachineTerminalPresentation(
                    controller: controller,
                    title: "Container terminal"
                )
            } catch {
                machineTerminalErrorPresented = true
            }
            machineTerminalOpening = false
        }
    }
}

// swiftlint:enable type_body_length

private struct MachineTerminalPresentation: Identifiable {
    let id = UUID()
    let controller: TerminalSessionController
    let title: LocalizedStringKey
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

import MCAppCore
import MCContracts
import MCModel
import MCTemplates
import SwiftUI

struct SimpleModeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplateID: String
    @State private var imageReference = "alpine:latest"
    @State private var workspaceDirectory = "/tmp/maccontainer-workspace"
    @State private var volumeName = "maccontainer-data"
    @State private var hostPort = "8080"
    @State private var advancedPresented = false
    @State private var reviewPresented = false
    @State private var libraryPresented = false
    @State private var statusMessage: String?
    @State private var compactSection: CompactSection = .templates

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private enum CompactSection {
        case templates
        case configuration
    }

    init(initialTemplateID: String = "quick-run") {
        _selectedTemplateID = State(initialValue: initialTemplateID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("close-simple-mode")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            GeometryReader { proxy in
                if proxy.size.width >= 900 {
                    HSplitView {
                        templateList
                            .frame(minWidth: 300, idealWidth: 360)
                        configuration
                            .frame(minWidth: 420, idealWidth: 560)
                    }
                } else {
                    VStack(spacing: 0) {
                        compactSectionPicker
                        Divider()
                        switch compactSection {
                        case .templates:
                            templateList
                        case .configuration:
                            configuration
                        }
                    }
                }
            }
        }
        .frame(minHeight: 660)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenario template builder")
        .accessibilityIdentifier("simple-mode")
        .sheet(isPresented: $reviewPresented) {
            if let template = selectedTemplate, let review {
                TemplateReviewView(
                    template: template,
                    review: review,
                    contract: Self.contract,
                    isPresented: $reviewPresented
                ) {
                    try await run(review)
                }
            }
        }
        .sheet(isPresented: $libraryPresented) {
            TemplateLibraryView(isPresented: $libraryPresented)
        }
    }

    private var compactSectionPicker: some View {
        HStack(spacing: 8) {
            compactSectionButton(
                "1. Choose scenario",
                symbol: "square.grid.2x2",
                section: .templates,
                identifier: "template-section.templates"
            )
            compactSectionButton(
                "2. Configure",
                symbol: "slider.horizontal.3",
                section: .configuration,
                identifier: "template-section.configuration"
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Template workflow steps")
    }

    private func compactSectionButton(
        _ title: LocalizedStringKey,
        symbol: String,
        section: CompactSection,
        identifier: String
    ) -> some View {
        Button {
            compactSection = section
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    compactSection == section ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(compactSection == section ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityValue(compactSection == section ? "Selected" : "")
        .accessibilityIdentifier(identifier)
    }

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("What do you want to do?")
                        .font(.title.bold())
                    Text("Choose an outcome. MacContainer fills in safe, host-aware defaults.")
                        .fontWeight(.medium)
                        .readableForeground()
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(BuiltInTemplates.all) { template in
                        templateCard(template)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Available scenario templates")

                Button {
                    libraryPresented = true
                } label: {
                    Label("Manage templates", systemImage: "square.stack.3d.up")
                }
                .accessibilityIdentifier("manage-templates")
            }
            .padding(20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose a scenario template")
    }

    private var configuration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let metadata = selectedTemplate.map(TemplateMetadata.init) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(metadata.title, systemImage: metadata.symbol)
                            .font(.title2.bold())
                        Text(metadata.summary)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(nsColor: .labelColor))
                    }
                }

                GroupBox("Required choices") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Image") {
                            TextField("Image reference", text: $imageReference)
                                .frame(minWidth: 280)
                                .accessibilityIdentifier("template-choice.image")
                        }
                        if selectedTemplateID == "web-service" || selectedTemplateID == "local-database" {
                            LabeledContent("Host port") {
                                TextField("8080", text: $hostPort)
                                    .frame(width: 120)
                                    .accessibilityIdentifier("template-choice.port")
                            }
                        }
                        if selectedTemplateID == "development-workspace" {
                            LabeledContent("Workspace folder") {
                                TextField("Absolute path", text: $workspaceDirectory)
                                    .accessibilityIdentifier("template-choice.directory")
                            }
                        }
                        if selectedTemplateID == "local-database" {
                            LabeledContent("Data volume") {
                                TextField("Volume name", text: $volumeName)
                                    .accessibilityIdentifier("template-choice.volume")
                            }
                        }
                    }
                    .padding(8)
                }

                safeguards

                Button {
                    advancedPresented.toggle()
                } label: {
                    Label("Advanced", systemImage: advancedPresented ? "chevron.down" : "chevron.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("template-advanced")

                if advancedPresented {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Generated values remain fully editable in review.")
                        Text("CPU and memory are recommended from this Mac, image metadata, and the selected scenario.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                HStack {
                    Spacer()
                    Button("Review all values") {
                        reviewPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(review == nil)
                    .accessibilityIdentifier("template-review")
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .accessibilityIdentifier("template-configuration-scroll")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Configure the selected scenario")
    }

    @ViewBuilder
    private var safeguards: some View {
        switch selectedTemplateID {
        case "restricted-secure":
            safetyLabel("Read-only root filesystem", symbol: "lock.shield.fill")
            safetyLabel("Network and DNS disabled", symbol: "network.slash")
        case "local-database":
            safetyLabel("Persistent data: \(volumeName)", symbol: "externaldrive.fill")
            safetyLabel("Graceful stop: 30 seconds", symbol: "clock.fill")
        case "cross-architecture":
            safetyLabel("Rosetta is required and will be checked before run.", symbol: "checkmark.shield.fill")
        case "linux-machine-workspace":
            safetyLabel("Home sharing disabled during creation", symbol: "house.fill")
            safetyLabel("Nested virtualization disabled during creation", symbol: "cpu")
            Text("Use Configure after creation to enable either capability with explicit consent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            safetyLabel("Uses local-only, least-privilege defaults", symbol: "checkmark.shield.fill")
        }
    }

    private func safetyLabel(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func templateCard(_ template: ScenarioTemplate) -> some View {
        let metadata = TemplateMetadata(template)
        return Button {
            selectedTemplateID = template.id
            compactSection = .configuration
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: metadata.symbol)
                    .font(.title3)
                    .foregroundStyle(selectedTemplateID == template.id ? Color.white : Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata.title)
                        .font(.headline)
                    Text(metadata.shortSummary)
                        .font(.caption)
                        .foregroundStyle(selectedTemplateID == template.id ? .white.opacity(0.85) : .secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(
                selectedTemplateID == template.id ? Color.accentColor : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .foregroundStyle(selectedTemplateID == template.id ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Selects this scenario and opens configuration")
        .accessibilityIdentifier("template.\(template.id)")
    }

    private var selectedTemplate: ScenarioTemplate? {
        BuiltInTemplates.all.first { $0.id == selectedTemplateID }
    }

    private var review: TemplateReview? {
        guard let selectedTemplate else { return nil }
        return try? TemplateRenderer(contract: Self.contract).render(
            template: selectedTemplate,
            context: context
        )
    }

    private var context: TemplateContext {
        let process = ProcessInfo.processInfo
        let macOSMajor = process.operatingSystemVersion.majorVersion
        var capabilities: Set<String> = []
        if macOSMajor >= 26 {
            capabilities.insert("nestedVirtualization")
        }
        if FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime") {
            capabilities.insert("rosetta")
        }
        return TemplateContext(
            host: HostProfile(
                logicalCPUs: max(1, process.activeProcessorCount),
                physicalMemoryBytes: Int64(clamping: process.physicalMemory),
                chip: .appleSilicon,
                macOSMajor: macOSMajor,
                capabilities: capabilities
            ),
            image: ImageProfile(
                reference: imageReference,
                defaultCommand: [],
                shells: ["/bin/sh"],
                platform: "linux/arm64",
                exposedPorts: [8080]
            ),
            selectedDirectory: workspaceDirectory,
            selectedVolume: volumeName,
            hostPort: UInt16(hostPort),
            containerPort: 8080
        )
    }

    private func run(_ review: TemplateReview) async throws -> String {
        let result = try await state.operationExecutor.execute(review.draft)
        let summary = "\(result.summary) · \(review.rows.count) reviewed values"
        statusMessage = summary
        return summary
    }

    private static let contract: UpstreamContract = {
        do {
            return try ContractRepository.bundled(
                version: RuntimeVersion(major: 1, minor: 1, patch: 0)
            )
        } catch {
            preconditionFailure("Bundled Apple container contract is unavailable: \(error)")
        }
    }()
}

struct TemplateMetadata {
    let title: LocalizedStringKey
    let summary: LocalizedStringKey
    let shortSummary: LocalizedStringKey
    let symbol: String

    init(_ template: ScenarioTemplate) {
        switch template.id {
        case "quick-run":
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Run once"),
                LocalizedStringKey("Start one container in the foreground with conservative resources."),
                LocalizedStringKey("Fast foreground run"), "play.circle.fill"
            )
        case "interactive-shell":
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Interactive shell"),
                LocalizedStringKey("Open the image's supported shell and remove the container on exit."),
                LocalizedStringKey("Temporary shell session"), "terminal.fill"
            )
        case "web-service":
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Web service"),
                LocalizedStringKey("Run a background service bound only to localhost by default."),
                LocalizedStringKey("Local web endpoint"), "network"
            )
        case "development-workspace":
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Development workspace"),
                LocalizedStringKey("Mount one selected project folder into an isolated workspace."),
                LocalizedStringKey("Code in a container"), "hammer.fill"
            )
        case "local-database":
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Local database"),
                LocalizedStringKey("Keep database files in a named volume and stop gracefully."),
                LocalizedStringKey("Persistent local data"), "cylinder.fill"
            )
        case "restricted-secure":
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Restricted workload"),
                LocalizedStringKey("Use a read-only filesystem with capabilities and networking removed."),
                LocalizedStringKey("Maximum isolation"), "lock.shield.fill"
            )
        case "cross-architecture":
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Intel workload"),
                LocalizedStringKey("Run an amd64 Linux image only after Rosetta compatibility checks pass."),
                LocalizedStringKey("Checked Rosetta run"), "cpu.fill"
            )
        default:
            (title, summary, shortSummary, symbol) = (
                LocalizedStringKey("Linux machine"),
                LocalizedStringKey("Create a persistent Linux machine with sharing and nesting disabled."),
                LocalizedStringKey("Persistent VM workspace"), "desktopcomputer"
            )
        }
    }
}

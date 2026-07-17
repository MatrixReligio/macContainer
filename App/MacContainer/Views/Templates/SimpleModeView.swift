import MCAppCore
import MCContracts
import MCModel
import MCTemplates
import SwiftUI

struct SimpleModeView: View {
    @Environment(AppState.self) private var state

    @State private var selectedTemplateID = "quick-run"
    @State private var imageReference = "alpine:latest"
    @State private var workspaceDirectory = "/tmp/maccontainer-workspace"
    @State private var volumeName = "maccontainer-data"
    @State private var hostPort = "8080"
    @State private var homeSharingConsent = false
    @State private var nestedVirtualizationConsent = false
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

    var body: some View {
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
                    run(review)
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
        _ title: String,
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
                        .foregroundStyle(Color(nsColor: .labelColor))
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
            Toggle("Share my home folder", isOn: $homeSharingConsent)
                .toggleStyle(.switch)
                .accessibilityIdentifier("consent.home-sharing")
                .accessibilityValue(Text(homeSharingConsent ? "On" : "Off"))
            Toggle("Enable nested virtualization", isOn: $nestedVirtualizationConsent)
                .toggleStyle(.switch)
                .accessibilityIdentifier("consent.nested-virtualization")
                .accessibilityValue(Text(nestedVirtualizationConsent ? "On" : "Off"))
            Text(
                "Home sharing: \(homeSharingConsent ? "On" : "Off") · " +
                    "Nested virtualization: \(nestedVirtualizationConsent ? "On" : "Off")"
            )
            .font(.caption.bold())
            .accessibilityIdentifier("consent.virtualization-status")
            Text("Both high-impact capabilities remain off unless you explicitly enable them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            safetyLabel("Uses local-only, least-privilege defaults", symbol: "checkmark.shield.fill")
        }
    }

    private func safetyLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func templateCard(_ template: ScenarioTemplate) -> some View {
        let metadata = TemplateMetadata(template)
        return Button {
            selectedTemplateID = template.id
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
        TemplateContext(
            host: HostProfile(
                logicalCPUs: 8,
                physicalMemoryBytes: 16 * 1_073_741_824,
                chip: .appleSilicon,
                macOSMajor: 26,
                capabilities: ["rosetta", "nestedVirtualization"]
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

    private func run(_ review: TemplateReview) {
        let id = state.activities.start(titleKey: "activity.template.\(selectedTemplateID)")
        state.activities.finish(id, outcome: .succeeded)
        statusMessage = "Started safely with \(review.rows.count) reviewed values"
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

private struct TemplateMetadata {
    let title: String
    let summary: String
    let shortSummary: String
    let symbol: String

    init(_ template: ScenarioTemplate) {
        switch template.id {
        case "quick-run":
            (title, summary, shortSummary, symbol) = (
                "Run once", "Start one container in the foreground with conservative resources.",
                "Fast foreground run", "play.circle.fill"
            )
        case "interactive-shell":
            (title, summary, shortSummary, symbol) = (
                "Interactive shell", "Open the image's supported shell and remove the container on exit.",
                "Temporary shell session", "terminal.fill"
            )
        case "web-service":
            (title, summary, shortSummary, symbol) = (
                "Web service", "Run a background service bound only to localhost by default.",
                "Local web endpoint", "network"
            )
        case "development-workspace":
            (title, summary, shortSummary, symbol) = (
                "Development workspace", "Mount one selected project folder into an isolated workspace.",
                "Code in a container", "hammer.fill"
            )
        case "local-database":
            (title, summary, shortSummary, symbol) = (
                "Local database", "Keep database files in a named volume and stop gracefully.",
                "Persistent local data", "cylinder.fill"
            )
        case "restricted-secure":
            (title, summary, shortSummary, symbol) = (
                "Restricted workload", "Use a read-only filesystem with capabilities and networking removed.",
                "Maximum isolation", "lock.shield.fill"
            )
        case "cross-architecture":
            (title, summary, shortSummary, symbol) = (
                "Intel workload", "Run an amd64 Linux image only after Rosetta compatibility checks pass.",
                "Checked Rosetta run", "cpu.fill"
            )
        default:
            (title, summary, shortSummary, symbol) = (
                "Linux machine", "Create a persistent Linux machine with sharing and nesting disabled.",
                "Persistent VM workspace", "desktopcomputer"
            )
        }
    }
}

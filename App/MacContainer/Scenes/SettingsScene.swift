import SwiftUI

struct SettingsScene: View {
    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
                    .accessibilityIdentifier("settings-pane.\(pane.rawValue)")
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .accessibilityLabel("Settings categories")
        } detail: {
            selectedPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.title)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Settings content")
                .accessibilityIdentifier("settings-content.\(selection.rawValue)")
        }
        .frame(minWidth: 760, minHeight: 620)
        .accessibilityIdentifier("settings-scene")
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
        case .runtime:
            RuntimeSettingsView()
        case .runtimeUpdates:
            RuntimeUpdateSettingsView()
        case .compatibility:
            CompatibilitySettingsView()
        case .defaults:
            DefaultsSettingsView()
        case .advanced:
            AdvancedSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case runtime
    case runtimeUpdates = "runtime-updates"
    case compatibility
    case defaults
    case advanced
    case about

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .general: LocalizedStringKey("General")
        case .runtime: LocalizedStringKey("Runtime")
        case .runtimeUpdates: LocalizedStringKey("Runtime Updates")
        case .compatibility: LocalizedStringKey("Compatibility")
        case .defaults: LocalizedStringKey("Defaults & Templates")
        case .advanced: LocalizedStringKey("Advanced")
        case .about: LocalizedStringKey("About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .runtime: "shippingbox"
        case .runtimeUpdates: "arrow.triangle.2.circlepath"
        case .compatibility: "checkmark.shield"
        case .defaults: "slider.horizontal.3"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

import SwiftUI

struct SettingsScene: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RuntimeSettingsView()
                .tabItem { Label("Runtime", systemImage: "shippingbox") }
            RuntimeUpdateSettingsView()
                .tabItem { Label("Runtime Updates", systemImage: "arrow.triangle.2.circlepath") }
            CompatibilitySettingsView()
                .tabItem { Label("Compatibility", systemImage: "checkmark.shield") }
            DefaultsSettingsView()
                .tabItem { Label("Defaults & Templates", systemImage: "slider.horizontal.3") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 820, height: 620)
    }
}

import MCAppCore
import SwiftUI

struct Sidebar: View {
    @Binding var selection: AppRoute

    var body: some View {
        List {
            Section("Manage") {
                ForEach(AppRoute.allCases, id: \.self) { route in
                    Button {
                        selection = route
                    } label: {
                        Label {
                            Text(LocalizedStringKey(route.title))
                        } icon: {
                            Image(systemName: route.symbol)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selection == route ? Color.accentColor.opacity(0.16) : Color.clear)
                    .accessibilityValue(selection == route ? "Selected" : "")
                    .accessibilityIdentifier("route.\(route.rawValue)")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MacContainer")
        .accessibilityIdentifier("sidebar")
    }
}

extension AppRoute {
    var title: String {
        switch self {
        case .overview: "Overview"
        case .containers: "Containers"
        case .images: "Images"
        case .builds: "Builds"
        case .machines: "Machines"
        case .networks: "Networks"
        case .volumes: "Volumes"
        case .registries: "Registries"
        case .system: "System"
        }
    }

    var singularTitle: String {
        switch self {
        case .overview: "item"
        case .containers: "container"
        case .images: "image"
        case .builds: "build"
        case .machines: "machine"
        case .networks: "network"
        case .volumes: "volume"
        case .registries: "registry"
        case .system: "system item"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .containers: "shippingbox"
        case .images: "photo.on.rectangle.angled"
        case .builds: "hammer"
        case .machines: "desktopcomputer"
        case .networks: "network"
        case .volumes: "externaldrive"
        case .registries: "lock.shield"
        case .system: "gearshape.2"
        }
    }
}

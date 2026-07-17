import MCAppCore
import SwiftUI

struct RootScene: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state

        NavigationSplitView(columnVisibility: $state.columnVisibility) {
            Sidebar(selection: $state.selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            RouteContentView(route: state.selection)
                .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        } detail: {
            ResourceInspectorPlaceholder(route: state.selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 340)
        }
        .frame(minWidth: 940, minHeight: 620)
        .background(WindowAccessibilityIdentifier("main-window"))
        .onChange(of: state.activityCenterPresented) {
            openWindow(id: "activity-center")
        }
    }
}

private struct RouteContentView: View {
    let route: AppRoute

    var body: some View {
        if route == .overview {
            OverviewView()
        } else {
            EmptyStateView(
                symbol: route.symbol,
                title: route.title,
                message: "No \(route.title.lowercased()) are available yet."
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(route.rawValue)-content")
            .navigationTitle(route.title)
        }
    }
}

private struct ResourceInspectorPlaceholder: View {
    let route: AppRoute

    var body: some View {
        ContentUnavailableView(
            "Nothing Selected",
            systemImage: "sidebar.right",
            description: Text("Select a \(route.singularTitle.lowercased()) to inspect its details.")
        )
        .accessibilityIdentifier("resource-inspector")
    }
}

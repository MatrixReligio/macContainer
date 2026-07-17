import MCAppCore
import SwiftUI

struct ResourceDomainView: View {
    @Environment(AppState.self) private var state
    let route: AppRoute

    var body: some View {
        ResourceTable(route: route, resources: state.resourceBrowser.resources(for: route))
            .task(id: route) {
                await state.resourceBrowser.refresh(route)
            }
    }
}

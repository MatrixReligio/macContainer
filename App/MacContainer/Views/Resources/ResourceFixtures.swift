import MCAppCore
import SwiftUI

struct ResourceDomainView: View {
    let route: AppRoute

    var body: some View {
        ResourceTable(route: route, resources: ResourceFixtures.rows(for: route))
    }
}

private enum ResourceFixtures {
    static func rows(for route: AppRoute) -> [ResourceRow] {
        switch route {
        case .overview:
            []
        case .containers:
            [
                ResourceRow(
                    id: "demo-web",
                    name: "demo-web",
                    status: "Running",
                    detail: "alpine:latest",
                    isProtected: false
                )
            ]
        case .images:
            [
                ResourceRow(
                    id: "alpine:latest",
                    name: "alpine:latest",
                    status: "Ready",
                    detail: "8.1 MB",
                    isProtected: false
                )
            ]
        case .builds:
            [ResourceRow(id: "last-build", name: "Last build", status: "Ready", detail: "Just now", isProtected: false)]
        case .machines:
            [ResourceRow(id: "default", name: "default", status: "Running", detail: "4 CPU · 4 GB", isProtected: false)]
        case .networks:
            [ResourceRow(id: "default", name: "default", status: "Ready", detail: "Built-in", isProtected: true)]
        case .volumes:
            [ResourceRow(id: "workspace", name: "workspace", status: "Ready", detail: "Local", isProtected: false)]
        case .registries:
            [ResourceRow(id: "ghcr.io", name: "ghcr.io", status: "Connected", detail: "Credentials protected", isProtected: false)]
        case .system:
            [
                ResourceRow(
                    id: "apple-container",
                    name: "Apple container service",
                    status: "Running",
                    detail: "Compatible",
                    isProtected: true
                )
            ]
        }
    }
}

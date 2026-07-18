import MCAppCore
import SwiftUI

struct TerminalSessionView: View {
    let controller: TerminalSessionController

    @State private var status = TerminalPresentationStatus.connected
    @State private var readerActive = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Direct interactive session")
                        .font(.headline)
                    Text("Remote clipboard, links, notifications, and title changes are blocked.")
                        .font(.subheadline.weight(.semibold))
                        .readableForeground()
                }
                Spacer()
                Label {
                    Text(status.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(nsColor: .labelColor))
                } icon: {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.tint)
                }
            }
            .padding()

            Divider()
            SwiftTermRepresentable(controller: controller)
                .frame(minWidth: 720, minHeight: 480)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Interactive container terminal")
                .accessibilityIdentifier("swiftterm-surface")

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reduced motion: terminal output updates without decorative animation.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(LocalizedStringKey(
                        readerActive ? "Reader task active" : "Reader task stopped"
                    ))
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                }
                Spacer()
                Button("Detach") {
                    close(.detach)
                }
                .accessibilityIdentifier("terminal-detach")
                Button("Terminate") {
                    close(.terminate(signal: "TERM"))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("terminal-terminate")
            }
            .padding()
        }
        .frame(minWidth: 820, minHeight: 620)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-session")
    }

    private func close(_ choice: TerminalCloseChoice) {
        Task {
            do {
                try await controller.close(choice)
                readerActive = false
                switch choice {
                case .detach:
                    status = .detached
                case let .terminate(signal):
                    status = .terminated(
                        signal.uppercased().replacingOccurrences(of: "SIG", with: "")
                    )
                }
            } catch {
                status = .closeFailed
            }
        }
    }
}

private enum TerminalPresentationStatus {
    case connected
    case detached
    case terminated(String)
    case closeFailed

    var title: LocalizedStringKey {
        switch self {
        case .connected: "Connected"
        case .detached: "Detached — workload keeps running"
        case let .terminated(signal): "Terminated with SIG\(signal)"
        case .closeFailed: "Close failed — session state unchanged"
        }
    }

    var symbol: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .detached, .terminated: "info.circle.fill"
        case .closeFailed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .detached, .terminated: .orange
        case .closeFailed: .red
        }
    }
}

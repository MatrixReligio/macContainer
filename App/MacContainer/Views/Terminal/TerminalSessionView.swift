import MCAppCore
import SwiftUI

struct TerminalSessionView: View {
    let controller: TerminalSessionController

    @State private var status = "Connected"
    @State private var readerStatus = "Reader task active"

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
                    Text(status)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(nsColor: .labelColor))
                } icon: {
                    Image(systemName: status == "Connected" ? "checkmark.circle.fill" : "info.circle.fill")
                        .foregroundStyle(status == "Connected" ? .green : .orange)
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
                    Text(readerStatus)
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
                readerStatus = "Reader task stopped"
                switch choice {
                case .detach:
                    status = "Detached — workload keeps running"
                case let .terminate(signal):
                    status = "Terminated with SIG\(signal.uppercased().replacingOccurrences(of: "SIG", with: ""))"
                }
            } catch {
                status = "Close failed — session state unchanged"
            }
        }
    }
}

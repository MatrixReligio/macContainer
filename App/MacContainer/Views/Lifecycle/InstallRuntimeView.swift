import SwiftUI

struct InstallRuntimeView: View {
    private enum InstallPhase {
        case ready
        case postflightPending
        case complete
    }

    @State private var phase: InstallPhase = .ready
    let isAuditMode: Bool

    init(isAuditMode: Bool = false) {
        self.isAuditMode = isAuditMode
    }

    var body: some View {
        GroupBox("Install Apple container") {
            VStack(alignment: .leading, spacing: 9) {
                Label("Apple container 1.1.0", systemImage: "shippingbox.fill")
                    .font(.headline)
                Text("Source: developer.apple.com")
                Text("Signer: Apple Inc. - Containerization (UPBK2H6LZM)")
                    .font(.caption)
                Label("SHA-256 digest verified", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Disk impact: up to 420 MB")
                Text("Administrator approval is requested only when installation begins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Review and install") {
                    phase = .postflightPending
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("install-runtime")

                if phase == .postflightPending {
                    Label("Installing — compatibility postflight pending", systemImage: "hourglass")
                    if isAuditMode {
                        Button("Complete simulated postflight") {
                            phase = .complete
                        }
                        .accessibilityIdentifier("simulate-install-postflight")
                    }
                } else if phase == .complete {
                    Label("Runtime ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

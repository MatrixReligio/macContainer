import SwiftUI

struct DestructiveConfirmation: View {
    let resourceKind: String
    let resourceIDs: [String]
    @Binding var isPresented: Bool
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Delete \(resourceKind.capitalized)")
                    .font(.title2.bold())
            }

            GroupBox("Affected resources") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(resourceIDs, id: \.self) { resourceID in
                        Text(resourceID)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("This action permanently removes the selected \(resourceKind.lowercased()).")
            Text("Re-create it from a template or backup if you need it again.")
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    confirm()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("destructive-confirmation")
    }
}

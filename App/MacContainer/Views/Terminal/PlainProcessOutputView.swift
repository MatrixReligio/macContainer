import MCAppCore
import SwiftUI

struct PlainProcessOutputView: View {
    let controller: TerminalSessionController

    @State private var stdout = ""
    @State private var stderr = ""

    var body: some View {
        HSplitView {
            outputPane(
                title: LocalizedStringKey("Standard output"),
                text: stdout,
                identifier: "plain-stdout"
            )
            outputPane(
                title: LocalizedStringKey("Standard error"),
                text: stderr,
                identifier: "plain-stderr"
            )
        }
        .task {
            await controller.start { event in
                await MainActor.run {
                    switch event {
                    case let .stdout(text):
                        stdout.append(text)
                    case let .stderr(text):
                        stderr.append(text)
                    case .terminal:
                        break
                    }
                }
            }
        }
    }

    private func outputPane(
        title: LocalizedStringKey,
        text: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ScrollView {
                Text(verbatim: text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .accessibilityIdentifier(identifier)
        }
        .padding()
    }
}

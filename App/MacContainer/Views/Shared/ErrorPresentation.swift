import MCModel
import SwiftUI

enum ErrorPresentationStyle {
    case immediate
    case activity
}

struct ErrorPresentation: View {
    let error: UserFacingError
    let style: ErrorPresentationStyle
    let perform: (ErrorRecoveryAction) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(LocalizedStringKey(error.titleKey))
                        .foregroundStyle(Color(nsColor: .labelColor))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.headline)
                Text(LocalizedStringKey(error.explanationKey))
                if style == .activity {
                    Text(error.diagnosticDetail)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("error-diagnostic")
                }
                HStack {
                    ForEach(error.recoveryActions) { action in
                        Button(LocalizedStringKey(action.titleKey)) {
                            perform(action)
                        }
                        .accessibilityIdentifier("error-action.\(action.id)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("error-presentation")
    }
}

private struct ImmediateErrorModifier: ViewModifier {
    @Binding var error: UserFacingError?

    func body(content: Content) -> some View {
        content.alert(
            LocalizedStringKey(error?.titleKey ?? ""),
            isPresented: Binding(
                get: { error != nil },
                set: {
                    if !$0 {
                        error = nil
                    }
                }
            ),
            presenting: error
        ) { error in
            ForEach(error.recoveryActions) { action in
                Button(LocalizedStringKey(action.titleKey)) {}
            }
            Button("Cancel", role: .cancel) {
                self.error = nil
            }
        } message: { error in
            Text(LocalizedStringKey(error.explanationKey))
        }
    }
}

extension View {
    func immediateError(_ error: Binding<UserFacingError?>) -> some View {
        modifier(ImmediateErrorModifier(error: error))
    }
}

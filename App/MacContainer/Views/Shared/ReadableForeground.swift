import SwiftUI

private struct ReadableForegroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
    }
}

extension View {
    func readableForeground() -> some View {
        modifier(ReadableForegroundModifier())
    }
}

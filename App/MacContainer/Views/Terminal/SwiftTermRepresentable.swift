import AppKit
import MCAppCore
import SwiftTerm
import SwiftUI

struct SwiftTermRepresentable: NSViewRepresentable {
    let controller: TerminalSessionController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.textArea)
        view.setAccessibilityIdentifier("swiftterm-surface")
        view.setAccessibilityLabel("Interactive container terminal")
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_: TerminalView, context _: Context) {}

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        view.terminalDelegate = nil
        coordinator.detachView()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        private let controller: TerminalSessionController
        private weak var view: TerminalView?

        init(controller: TerminalSessionController) {
            self.controller = controller
        }

        func attach(to view: TerminalView) {
            self.view = view
            Task { [controller, weak self] in
                await controller.start { [weak self] event in
                    await MainActor.run {
                        self?.render(event)
                    }
                }
            }
        }

        func detachView() {
            view = nil
            Task { [controller] in
                try? await controller.close(.detach)
            }
        }

        func send(source _: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Data(data)
            Task { [controller] in
                try? await controller.send(bytes)
            }
        }

        func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
            Task { [controller] in
                await controller.requestResize(columns: newCols, rows: newRows)
            }
        }

        func setTerminalTitle(source _: TerminalView, title _: String) {}
        func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {}
        func scrolled(source _: TerminalView, position _: Double) {}
        func requestOpenLink(source _: TerminalView, link _: String, params _: [String: String]) {}
        func bell(source _: TerminalView) {}
        func clipboardCopy(source _: TerminalView, content _: Data) {}
        func iTermContent(source _: TerminalView, content _: ArraySlice<UInt8>) {}
        func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {}

        private func render(_ event: TerminalRenderEvent) {
            guard let view else { return }
            switch event {
            case let .terminal(data):
                let bytes = [UInt8](data)
                view.feed(byteArray: bytes[...])
            case let .stdout(text), let .stderr(text):
                view.feed(text: text)
            }
        }
    }
}

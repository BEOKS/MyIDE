import AppKit
import SwiftUI
import MyIDECore

@MainActor
final class EmbeddedTerminalHostView: NSView {
    let terminalView: EmbeddedTerminalView

    init(paneID: String, configuration: TerminalPaneConfiguration) {
        self.terminalView = EmbeddedTerminalView(paneID: paneID, configuration: configuration)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(terminalView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        terminalView.frame = bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(terminalView)
    }

    func stopTerminal() {
        terminalView.stopTerminal()
    }
}

struct TerminalCommandEditorRepresentable: NSViewRepresentable {
    let paneID: String
    let configuration: TerminalPaneConfiguration

    func makeNSView(context: Context) -> EmbeddedTerminalHostView {
        EmbeddedTerminalHostView(paneID: paneID, configuration: configuration)
    }

    func updateNSView(_ nsView: EmbeddedTerminalHostView, context: Context) {
        _ = context
        _ = nsView
    }

    static func dismantleNSView(_ nsView: EmbeddedTerminalHostView, coordinator: ()) {
        _ = coordinator
        nsView.stopTerminal()
    }
}

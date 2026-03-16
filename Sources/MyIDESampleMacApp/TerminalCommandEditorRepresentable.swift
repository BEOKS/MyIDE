import SwiftUI
import MyIDECore

struct TerminalCommandEditorRepresentable: NSViewRepresentable {
    let paneID: String
    let configuration: TerminalPaneConfiguration

    func makeNSView(context: Context) -> EmbeddedTerminalView {
        EmbeddedTerminalView(paneID: paneID, configuration: configuration)
    }

    func updateNSView(_ nsView: EmbeddedTerminalView, context: Context) {
        _ = context
        _ = nsView
    }
}

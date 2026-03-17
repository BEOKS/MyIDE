import SwiftUI
import MyIDECore

struct TerminalCommandEditorRepresentable: NSViewRepresentable {
    let paneID: String
    let configuration: TerminalPaneConfiguration
    let onProcessTerminated: () -> Void

    func makeNSView(context: Context) -> EmbeddedTerminalView {
        EmbeddedTerminalView(
            paneID: paneID,
            configuration: configuration,
            onProcessTerminated: onProcessTerminated
        )
    }

    func updateNSView(_ nsView: EmbeddedTerminalView, context: Context) {
        _ = context
        _ = nsView
    }
}

import AppKit
import SwiftUI

@main
struct MyIDESampleMacApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        TerminalAutomationBridge.shared.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup("MyIDE") {
            sessionContent(sessionID: viewModel.workspace.sessions.first?.id)
        }

        WindowGroup("MyIDE", for: String.self) { $sessionID in
            sessionContent(sessionID: sessionID)
        }
    }

    @ViewBuilder
    private func sessionContent(sessionID: String?) -> some View {
        Group {
            if let resolvedSessionID = resolvedSessionID(from: sessionID) {
                ContentView(
                    sessionID: resolvedSessionID,
                    viewModel: viewModel,
                    onCreateSession: {
                        viewModel.addSession()?.id
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "macwindow",
                    description: Text("Create a new session to open a workspace window.")
                )
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func resolvedSessionID(from sessionID: String?) -> String? {
        if let sessionID, viewModel.session(id: sessionID) != nil {
            return sessionID
        }

        return viewModel.workspace.sessions.first?.id
    }
}

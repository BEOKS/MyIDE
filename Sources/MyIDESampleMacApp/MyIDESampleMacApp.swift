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
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
    }
}

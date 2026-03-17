import SwiftUI
import MyIDECore

struct ContentView: View {
    let sessionID: String
    @ObservedObject var viewModel: AppViewModel
    let onCreateSession: () -> String?

    @Environment(\.openWindow) private var openWindow
    @State private var selectedWindowID: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showingAddPaneSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .labelStyle(.iconOnly)
                .help("Add Pane")
                .disabled(selectedWindow == nil)
            }
        }
        .sheet(isPresented: $viewModel.showingAddPaneSheet) {
            AddPaneSheet { draft in
                guard let selectedWindowID else {
                    return
                }
                viewModel.addPane(sessionID: sessionID, windowID: selectedWindowID, draft: draft)
            }
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            ensureSelectedWindow()
        }
        .onChange(of: session?.windows.map(\.id) ?? []) { _, _ in
            ensureSelectedWindow()
        }
    }

    private var sidebar: some View {
        List {
            Section {
                Button("New Session") {
                    if let newSessionID = onCreateSession() {
                        openWindow(value: newSessionID)
                    }
                }

                Button("New Window") {
                    if let window = viewModel.addWindow(to: sessionID) {
                        selectedWindowID = window.id
                    }
                }
                .disabled(session == nil)
            }

            if let session {
                Section("Windows") {
                    ForEach(session.windows) { window in
                        Button {
                            selectedWindowID = window.id
                        } label: {
                            HStack {
                                Text(window.title)
                                Spacer()
                                Text("\(window.panes.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(session?.name ?? "Workspace")
    }

    @ViewBuilder
    private var detail: some View {
        if let window = selectedWindow {
            PaneWorkspaceView(
                panes: window.panes,
                onTerminalExit: { paneID in
                    viewModel.removePane(sessionID: sessionID, windowID: window.id, paneID: paneID)
                },
                onUpdateBrowser: { paneID, urlString in
                    viewModel.updateBrowserPane(sessionID: sessionID, windowID: window.id, paneID: paneID, urlString: urlString)
                },
                onRefreshDiff: { paneID, leftPath, rightPath in
                    viewModel.refreshDiffPane(
                        sessionID: sessionID,
                        windowID: window.id,
                        paneID: paneID,
                        leftPath: leftPath,
                        rightPath: rightPath
                    )
                },
                onUpdateDiffPaths: { paneID, leftPath, rightPath in
                    viewModel.updateDiffPanePaths(
                        sessionID: sessionID,
                        windowID: window.id,
                        paneID: paneID,
                        leftPath: leftPath,
                        rightPath: rightPath
                    )
                },
                onUpdatePreviewPath: { paneID, filePath in
                    viewModel.updatePreviewPanePath(sessionID: sessionID, windowID: window.id, paneID: paneID, filePath: filePath)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        } else if session != nil {
            ContentUnavailableView(
                "No Window Selected",
                systemImage: "rectangle.split.2x1",
                description: Text("Create a window to add it to the left navigation bar.")
            )
        } else {
            ContentUnavailableView(
                "No Session Selected",
                systemImage: "sidebar.left",
                description: Text("Create a new session to open a workspace window.")
            )
        }
    }

    private var session: WorkspaceSession? {
        viewModel.session(id: sessionID)
    }

    private var selectedWindow: WorkspaceWindow? {
        guard let selectedWindowID else {
            return nil
        }

        return viewModel.window(sessionID: sessionID, windowID: selectedWindowID)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func ensureSelectedWindow() {
        guard let session else {
            selectedWindowID = nil
            return
        }

        if let selectedWindowID,
           session.windows.contains(where: { $0.id == selectedWindowID }) {
            return
        }

        selectedWindowID = session.windows.first?.id
    }
}

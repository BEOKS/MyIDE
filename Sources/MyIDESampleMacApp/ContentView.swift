import SwiftUI
import MyIDECore

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

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
                .disabled(viewModel.selectedWindow == nil)
            }
        }
        .sheet(isPresented: $viewModel.showingAddPaneSheet) {
            AddPaneSheet { draft in
                viewModel.addPane(draft: draft)
            }
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        List {
            Section {
                Button("New Session") {
                    viewModel.addSession()
                }

                Button("New Window") {
                    viewModel.addWindow()
                }
                .disabled(viewModel.selectedSession == nil)
            }

            ForEach(viewModel.workspace.sessions) { session in
                Section(session.name) {
                    ForEach(session.windows) { window in
                        Button {
                            viewModel.select(sessionID: session.id, windowID: window.id)
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
        .navigationTitle("Workspace")
    }

    @ViewBuilder
    private var detail: some View {
        if let window = viewModel.selectedWindow {
            PaneWorkspaceView(
                panes: window.panes,
                onRemove: { paneID in
                    viewModel.removePane(paneID)
                },
                onUpdateBrowser: { paneID, urlString in
                    viewModel.updateBrowserPane(paneID: paneID, urlString: urlString)
                },
                onRefreshDiff: { paneID, leftPath, rightPath in
                    viewModel.refreshDiffPane(paneID: paneID, leftPath: leftPath, rightPath: rightPath)
                },
                onUpdatePreviewPath: { paneID, filePath in
                    viewModel.updatePreviewPanePath(paneID: paneID, filePath: filePath)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        } else {
            ContentUnavailableView(
                "No Window Selected",
                systemImage: "sidebar.left",
                description: Text("Create or select a session window to start working.")
            )
        }
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
}

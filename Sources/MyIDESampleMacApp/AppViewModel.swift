import Foundation
import MyIDECore

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var workspace: Workspace
    @Published var errorMessage: String?

    let persistenceURL: URL
    private var changeObserver: NSObjectProtocol?

    init() {
        persistenceURL = Self.defaultWorkspaceURL()

        do {
            workspace = try WorkspaceStore.loadOrCreate(at: persistenceURL, seed: Workspace.starter())
        } catch {
            workspace = Workspace.starter()
            errorMessage = error.localizedDescription
        }

        startWatchingExternalChanges()
    }

    deinit {
        if let changeObserver {
            DistributedNotificationCenter.default().removeObserver(changeObserver)
        }
    }

    private func startWatchingExternalChanges() {
        changeObserver = DistributedNotificationCenter.default().addObserver(
            forName: WorkspaceStore.workspaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { [weak self] in
                self?.reloadFromDisk(notification: notification)
            }
        }
    }

    private func reloadFromDisk(notification: Notification) {
        guard let senderPath = notification.object as? String,
              senderPath == persistenceURL.path else {
            return
        }

        do {
            workspace = try WorkspaceStore.load(from: persistenceURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func session(id: String) -> WorkspaceSession? {
        workspace.sessions.first(where: { $0.id == id })
    }

    func addSession() -> WorkspaceSession? {
        let name = "Session \(workspace.sessions.count + 1)"
        let session = workspace.addSession(named: name)

        do {
            _ = try workspace.addWindow(toSessionID: session.id, title: "Main")
            persist()
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func addWindow(to sessionID: String) -> WorkspaceWindow? {
        do {
            let session = try requireSession(id: sessionID)
            let window = try workspace.addWindow(
                toSessionID: sessionID,
                title: "Window \(session.windows.count + 1)"
            )
            persist()
            return window
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func addPane(sessionID: String, windowID: String, draft: AddPaneDraft) {
        do {
            let pane = draft.makePane()
            try workspace.addPane(pane, toSessionID: sessionID, windowID: windowID)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func splitWithTerminalPane(sessionID: String, windowID: String, paneID: String?, axis: PaneSplitAxis) -> WorkspacePane? {
        do {
            let pane = WorkspacePane.terminal(
                title: "Terminal",
                provider: .terminal,
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let newPane = try workspace.splitPane(
                sessionID: sessionID,
                windowID: windowID,
                paneID: paneID,
                axis: axis,
                newPane: pane
            )
            persist()
            return newPane
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func removePane(sessionID: String, windowID: String, paneID: String) {
        do {
            try workspace.removePane(sessionID: sessionID, windowID: windowID, paneID: paneID)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateBrowserPane(sessionID: String, windowID: String, paneID: String, urlString: String) {
        mutatePane(sessionID: sessionID, windowID: windowID, paneID: paneID) { pane in
            guard var browser = pane.browser else {
                throw WorkspaceError.invalidPane("Browser pane is not configured")
            }
            browser.urlString = urlString
            pane.browser = browser
        }
    }

    func refreshDiffPane(sessionID: String, windowID: String, paneID: String, leftPath: String, rightPath: String) {
        mutatePane(sessionID: sessionID, windowID: windowID, paneID: paneID) { pane in
            guard var diff = pane.diff else {
                throw WorkspaceError.invalidPane("Diff pane is not configured")
            }
            diff.leftPath = leftPath
            diff.rightPath = rightPath
            diff.lastDiff = try UnifiedDiffService.diff(leftPath: leftPath, rightPath: rightPath)
            pane.diff = diff
        }
    }

    func updateDiffPanePaths(sessionID: String, windowID: String, paneID: String, leftPath: String, rightPath: String) {
        mutatePane(sessionID: sessionID, windowID: windowID, paneID: paneID) { pane in
            guard var diff = pane.diff else {
                throw WorkspaceError.invalidPane("Diff pane is not configured")
            }
            diff.leftPath = leftPath
            diff.rightPath = rightPath
            pane.diff = diff
        }
    }

    func updatePreviewPanePath(sessionID: String, windowID: String, paneID: String, filePath: String) {
        mutatePane(sessionID: sessionID, windowID: windowID, paneID: paneID) { pane in
            guard var preview = pane.preview else {
                throw WorkspaceError.invalidPane("Preview pane is not configured")
            }
            preview.filePath = filePath
            pane.preview = preview
        }
    }

    func runTerminalCommand(paneID: String, command: String) {
        _ = paneID
        _ = command
    }

    func window(sessionID: String, windowID: String) -> WorkspaceWindow? {
        guard let session = session(id: sessionID) else {
            return nil
        }

        return session.windows.first(where: { $0.id == windowID })
    }

    private func mutatePane(
        sessionID: String,
        windowID: String,
        paneID: String,
        update: (inout WorkspacePane) throws -> Void
    ) {
        do {
            try workspace.updatePane(
                sessionID: sessionID,
                windowID: windowID,
                paneID: paneID,
                using: update
            )
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requireSession(id: String) throws -> WorkspaceSession {
        guard let session = workspace.sessions.first(where: { $0.id == id }) else {
            throw WorkspaceError.invalidPane("No session selected")
        }

        return session
    }

    private func persist() {
        do {
            try WorkspaceStore.save(workspace, to: persistenceURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func defaultWorkspaceURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let overridePath = environment["MYIDE_WORKSPACE_PATH"], !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return applicationSupport
            .appendingPathComponent("MyIDE", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }
}

struct AddPaneDraft {
    var title = ""
    var kind: PaneKind = .terminal
    var terminalProvider: TerminalProvider = .terminal
    var browserURL = "https://www.swift.org"
    var leftPath = ""
    var rightPath = ""
    var filePath = ""

    func makePane() -> WorkspacePane {
        switch kind {
        case .terminal:
            return .terminal(
                title: title.isEmpty ? "Terminal" : title,
                provider: terminalProvider,
                workingDirectory: FileManager.default.currentDirectoryPath
            )
        case .browser:
            return .browser(
                title: title.isEmpty ? "Browser" : title,
                urlString: browserURL
            )
        case .diff:
            return .diff(
                title: title.isEmpty ? "Diff" : title,
                leftPath: leftPath,
                rightPath: rightPath
            )
        case .markdownPreview:
            return .markdownPreview(
                title: title.isEmpty ? "Markdown" : title,
                filePath: filePath
            )
        case .imagePreview:
            return .imagePreview(
                title: title.isEmpty ? "Image" : title,
                filePath: filePath
            )
        }
    }
}

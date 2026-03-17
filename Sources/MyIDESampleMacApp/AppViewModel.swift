import Foundation
import MyIDECore

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var workspace: Workspace
    @Published var selectedSessionID: String?
    @Published var selectedWindowID: String?
    @Published var showingAddPaneSheet = false
    @Published var errorMessage: String?

    let persistenceURL: URL

    init() {
        persistenceURL = Self.defaultWorkspaceURL()

        do {
            workspace = try WorkspaceStore.loadOrCreate(at: persistenceURL, seed: Workspace.starter())
        } catch {
            workspace = Workspace.starter()
            errorMessage = error.localizedDescription
        }

        if let session = workspace.sessions.first {
            selectedSessionID = session.id
            selectedWindowID = session.windows.first?.id
        }
    }

    var selectedSession: WorkspaceSession? {
        guard let selectedSessionID else { return nil }
        return workspace.sessions.first(where: { $0.id == selectedSessionID })
    }

    var selectedWindow: WorkspaceWindow? {
        guard let selectedSession, let selectedWindowID else { return nil }
        return selectedSession.windows.first(where: { $0.id == selectedWindowID })
    }

    func select(sessionID: String, windowID: String) {
        selectedSessionID = sessionID
        selectedWindowID = windowID
    }

    func addSession() {
        let name = "Session \(workspace.sessions.count + 1)"
        let session = workspace.addSession(named: name)
        do {
            let window = try workspace.addWindow(toSessionID: session.id, title: "Window 1")
            select(sessionID: session.id, windowID: window.id)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addWindow() {
        guard let selectedSessionID else {
            addSession()
            return
        }

        do {
            let session = try requireSelectedSession()
            let window = try workspace.addWindow(
                toSessionID: selectedSessionID,
                title: "Window \(session.windows.count + 1)"
            )
            selectedWindowID = window.id
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPane(draft: AddPaneDraft) {
        guard let selectedSessionID, let selectedWindowID else { return }

        do {
            let pane = draft.makePane()
            try workspace.addPane(pane, toSessionID: selectedSessionID, windowID: selectedWindowID)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePane(_ paneID: String) {
        guard let selectedSessionID, let selectedWindowID else { return }

        do {
            try workspace.removePane(sessionID: selectedSessionID, windowID: selectedWindowID, paneID: paneID)
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateBrowserPane(paneID: String, urlString: String) {
        mutatePane(paneID: paneID) { pane in
            guard var browser = pane.browser else {
                throw WorkspaceError.invalidPane("Browser pane is not configured")
            }
            browser.urlString = urlString
            pane.browser = browser
        }
    }

    func refreshDiffPane(paneID: String, leftPath: String, rightPath: String) {
        mutatePane(paneID: paneID) { pane in
            guard var diff = pane.diff else {
                throw WorkspaceError.invalidPane("Diff pane is not configured")
            }
            diff.leftPath = leftPath
            diff.rightPath = rightPath
            diff.lastDiff = try UnifiedDiffService.diff(leftPath: leftPath, rightPath: rightPath)
            pane.diff = diff
        }
    }

    func updateDiffPanePaths(paneID: String, leftPath: String, rightPath: String) {
        mutatePane(paneID: paneID) { pane in
            guard var diff = pane.diff else {
                throw WorkspaceError.invalidPane("Diff pane is not configured")
            }
            diff.leftPath = leftPath
            diff.rightPath = rightPath
            pane.diff = diff
        }
    }

    func updatePreviewPanePath(paneID: String, filePath: String) {
        mutatePane(paneID: paneID) { pane in
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

    private func mutatePane(paneID: String, update: (inout WorkspacePane) throws -> Void) {
        guard let selectedSessionID, let selectedWindowID else { return }

        do {
            try workspace.updatePane(
                sessionID: selectedSessionID,
                windowID: selectedWindowID,
                paneID: paneID,
                using: update
            )
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requireSelectedSession() throws -> WorkspaceSession {
        guard let selectedSessionID,
              let session = workspace.sessions.first(where: { $0.id == selectedSessionID }) else {
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

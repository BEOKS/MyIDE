import Foundation

public enum PaneKind: String, Codable, CaseIterable {
    case terminal
    case browser
    case diff
    case markdownPreview
    case imagePreview
}

public struct PaneChromeConfiguration: Codable, Sendable {
    public var showsTitle: Bool
    public var showsCloseButton: Bool

    public init(showsTitle: Bool, showsCloseButton: Bool) {
        self.showsTitle = showsTitle
        self.showsCloseButton = showsCloseButton
    }

    public static let minimal = PaneChromeConfiguration(
        showsTitle: false,
        showsCloseButton: false
    )
}

public enum TerminalProvider: String, Codable, CaseIterable {
    case terminal
    case ghostty
    case iterm
}

public enum WorkspaceError: Error, LocalizedError {
    case sessionNotFound(String)
    case windowNotFound(String)
    case paneNotFound(String)
    case invalidPane(String)

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .windowNotFound(let id):
            return "Window not found: \(id)"
        case .paneNotFound(let id):
            return "Pane not found: \(id)"
        case .invalidPane(let message):
            return message
        }
    }
}

public struct Workspace: Codable {
    public var sessions: [WorkspaceSession]

    public init(sessions: [WorkspaceSession] = []) {
        self.sessions = sessions
    }

    public static func empty() -> Workspace {
        Workspace()
    }

    public static func starter() -> Workspace {
        let shell = WorkspacePane.terminal(
            title: "Shell",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let window = WorkspaceWindow(title: "Main", panes: [shell])
        let session = WorkspaceSession(name: "Main Session", windows: [window])
        return Workspace(sessions: [session])
    }

    public func session(withID id: String) -> WorkspaceSession? {
        sessions.first(where: { $0.id == id })
    }

    public func window(sessionID: String, windowID: String) throws -> WorkspaceWindow {
        guard let session = session(withID: sessionID) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        guard let window = session.windows.first(where: { $0.id == windowID }) else {
            throw WorkspaceError.windowNotFound(windowID)
        }

        return window
    }

    public func pane(sessionID: String, windowID: String, paneID: String) throws -> WorkspacePane {
        let window = try window(sessionID: sessionID, windowID: windowID)
        guard let pane = window.panes.first(where: { $0.id == paneID }) else {
            throw WorkspaceError.paneNotFound(paneID)
        }
        return pane
    }

    public mutating func addSession(named name: String) -> WorkspaceSession {
        let session = WorkspaceSession(name: name, windows: [])
        sessions.append(session)
        return session
    }

    @discardableResult
    public mutating func addWindow(toSessionID sessionID: String, title: String) throws -> WorkspaceWindow {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        let window = WorkspaceWindow(title: title, panes: [])
        sessions[sessionIndex].windows.append(window)
        return window
    }

    @discardableResult
    public mutating func addPane(_ pane: WorkspacePane, toSessionID sessionID: String, windowID: String) throws -> WorkspacePane {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        guard let windowIndex = sessions[sessionIndex].windows.firstIndex(where: { $0.id == windowID }) else {
            throw WorkspaceError.windowNotFound(windowID)
        }

        sessions[sessionIndex].windows[windowIndex].panes.append(pane)
        return pane
    }

    public mutating func updatePane(
        sessionID: String,
        windowID: String,
        paneID: String,
        using update: (inout WorkspacePane) throws -> Void
    ) throws {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        guard let windowIndex = sessions[sessionIndex].windows.firstIndex(where: { $0.id == windowID }) else {
            throw WorkspaceError.windowNotFound(windowID)
        }

        guard let paneIndex = sessions[sessionIndex].windows[windowIndex].panes.firstIndex(where: { $0.id == paneID }) else {
            throw WorkspaceError.paneNotFound(paneID)
        }

        try update(&sessions[sessionIndex].windows[windowIndex].panes[paneIndex])
    }

    public mutating func removePane(sessionID: String, windowID: String, paneID: String) throws {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        guard let windowIndex = sessions[sessionIndex].windows.firstIndex(where: { $0.id == windowID }) else {
            throw WorkspaceError.windowNotFound(windowID)
        }

        sessions[sessionIndex].windows[windowIndex].panes.removeAll { $0.id == paneID }
    }
}

public struct WorkspaceSession: Codable, Identifiable {
    public var id: String
    public var name: String
    public var windows: [WorkspaceWindow]

    public init(id: String = UUID().uuidString, name: String, windows: [WorkspaceWindow] = []) {
        self.id = id
        self.name = name
        self.windows = windows
    }
}

public struct WorkspaceWindow: Codable, Identifiable {
    public var id: String
    public var title: String
    public var panes: [WorkspacePane]

    public init(id: String = UUID().uuidString, title: String, panes: [WorkspacePane] = []) {
        self.id = id
        self.title = title
        self.panes = panes
    }
}

public struct WorkspacePane: Codable, Identifiable {
    public var id: String
    public var title: String
    public var kind: PaneKind
    public var terminal: TerminalPaneConfiguration?
    public var browser: BrowserPaneConfiguration?
    public var diff: DiffPaneConfiguration?
    public var preview: PreviewPaneConfiguration?

    public init(
        id: String = UUID().uuidString,
        title: String,
        kind: PaneKind,
        terminal: TerminalPaneConfiguration? = nil,
        browser: BrowserPaneConfiguration? = nil,
        diff: DiffPaneConfiguration? = nil,
        preview: PreviewPaneConfiguration? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.terminal = terminal
        self.browser = browser
        self.diff = diff
        self.preview = preview
    }

    public static func terminal(
        title: String,
        provider: TerminalProvider,
        workingDirectory: String
    ) -> WorkspacePane {
        WorkspacePane(
            title: title,
            kind: .terminal,
            terminal: TerminalPaneConfiguration(
                provider: provider,
                workingDirectory: workingDirectory,
                lastCommand: "",
                lastOutput: "",
                lastExitCode: nil
            )
        )
    }

    public static func browser(title: String, urlString: String) -> WorkspacePane {
        WorkspacePane(
            title: title,
            kind: .browser,
            browser: BrowserPaneConfiguration(urlString: urlString)
        )
    }

    public static func diff(title: String, leftPath: String, rightPath: String) -> WorkspacePane {
        WorkspacePane(
            title: title,
            kind: .diff,
            diff: DiffPaneConfiguration(
                leftPath: leftPath,
                rightPath: rightPath,
                lastDiff: ""
            )
        )
    }

    public static func markdownPreview(title: String, filePath: String) -> WorkspacePane {
        WorkspacePane(
            title: title,
            kind: .markdownPreview,
            preview: PreviewPaneConfiguration(filePath: filePath)
        )
    }

    public static func imagePreview(title: String, filePath: String) -> WorkspacePane {
        WorkspacePane(
            title: title,
            kind: .imagePreview,
            preview: PreviewPaneConfiguration(filePath: filePath)
        )
    }
}

public struct TerminalPaneConfiguration: Codable {
    public var provider: TerminalProvider
    public var workingDirectory: String
    public var lastCommand: String
    public var lastOutput: String
    public var lastExitCode: Int32?

    public init(
        provider: TerminalProvider,
        workingDirectory: String,
        lastCommand: String,
        lastOutput: String,
        lastExitCode: Int32?
    ) {
        self.provider = provider
        self.workingDirectory = workingDirectory
        self.lastCommand = lastCommand
        self.lastOutput = lastOutput
        self.lastExitCode = lastExitCode
    }
}

public struct BrowserPaneConfiguration: Codable {
    public var urlString: String

    public init(urlString: String) {
        self.urlString = urlString
    }
}

public struct DiffPaneConfiguration: Codable {
    public var leftPath: String
    public var rightPath: String
    public var lastDiff: String

    public init(leftPath: String, rightPath: String, lastDiff: String) {
        self.leftPath = leftPath
        self.rightPath = rightPath
        self.lastDiff = lastDiff
    }
}

public struct PreviewPaneConfiguration: Codable {
    public var filePath: String

    public init(filePath: String) {
        self.filePath = filePath
    }
}

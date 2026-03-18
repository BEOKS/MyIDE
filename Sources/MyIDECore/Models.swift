import Foundation

public enum PaneKind: String, Codable, CaseIterable {
    case picker
    case terminal
    case browser
    case diff
    case markdownPreview
    case imagePreview

    public static var creatableCases: [PaneKind] {
        [.terminal, .browser, .diff, .markdownPreview, .imagePreview]
    }

    public var displayTitle: String {
        switch self {
        case .picker:
            return "Choose Pane"
        case .terminal:
            return "Terminal"
        case .browser:
            return "Browser"
        case .diff:
            return "Diff"
        case .markdownPreview:
            return "Markdown"
        case .imagePreview:
            return "Image"
        }
    }
}

public enum PaneSplitAxis: String, Codable, Sendable {
    case vertical
    case horizontal
}

public enum PaneLayoutBranch: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
}

public struct PaneLayoutPath: Codable, Hashable, Sendable, Equatable, CustomStringConvertible {
    public static let root = PaneLayoutPath()

    public var components: [PaneLayoutBranch]

    public init(components: [PaneLayoutBranch] = []) {
        self.components = components
    }

    public init(parsing rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self = .root
            return
        }

        let parts = trimmed.split(separator: ".").map(String.init)
        guard parts.first == "root" else {
            throw WorkspaceError.invalidSplitPath(rawValue)
        }

        self.components = try parts.dropFirst().map { part in
            guard let branch = PaneLayoutBranch(rawValue: part) else {
                throw WorkspaceError.invalidSplitPath(rawValue)
            }

            return branch
        }
    }

    public var description: String {
        guard !components.isEmpty else {
            return "root"
        }

        return "root." + components.map(\.rawValue).joined(separator: ".")
    }

    public func appending(_ branch: PaneLayoutBranch) -> PaneLayoutPath {
        PaneLayoutPath(components: components + [branch])
    }
}

public struct PaneSplitDescriptor: Codable, Sendable, Equatable {
    public var path: String
    public var axis: PaneSplitAxis
    public var ratio: Double

    public init(path: String, axis: PaneSplitAxis, ratio: Double) {
        self.path = path
        self.axis = axis
        self.ratio = ratio
    }
}

public indirect enum PaneLayoutNode: Codable, Sendable, Equatable {
    case leaf(String)
    case split(axis: PaneSplitAxis, ratio: Double, primary: PaneLayoutNode, secondary: PaneLayoutNode)

    private enum CodingKeys: String, CodingKey {
        case kind
        case paneID
        case axis
        case ratio
        case primary
        case secondary
    }

    private enum NodeKind: String, Codable {
        case leaf
        case split
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(NodeKind.self, forKey: .kind) {
        case .leaf:
            self = .leaf(try container.decode(String.self, forKey: .paneID))
        case .split:
            self = .split(
                axis: try container.decode(PaneSplitAxis.self, forKey: .axis),
                ratio: try container.decodeIfPresent(Double.self, forKey: .ratio) ?? 0.5,
                primary: try container.decode(PaneLayoutNode.self, forKey: .primary),
                secondary: try container.decode(PaneLayoutNode.self, forKey: .secondary)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let paneID):
            try container.encode(NodeKind.leaf, forKey: .kind)
            try container.encode(paneID, forKey: .paneID)
        case .split(let axis, let ratio, let primary, let secondary):
            try container.encode(NodeKind.split, forKey: .kind)
            try container.encode(axis, forKey: .axis)
            try container.encode(ratio, forKey: .ratio)
            try container.encode(primary, forKey: .primary)
            try container.encode(secondary, forKey: .secondary)
        }
    }

    public func splitDescriptors(path: PaneLayoutPath = .root) -> [PaneSplitDescriptor] {
        switch self {
        case .leaf:
            return []
        case .split(let axis, let ratio, let primary, let secondary):
            return [
                PaneSplitDescriptor(
                    path: path.description,
                    axis: axis,
                    ratio: PaneSplitLayoutMetrics.clampedRatio(ratio)
                )
            ]
            + primary.splitDescriptors(path: path.appending(.primary))
            + secondary.splitDescriptors(path: path.appending(.secondary))
        }
    }

    public func splitDescriptor(at path: PaneLayoutPath) throws -> PaneSplitDescriptor {
        guard let descriptor = splitDescriptors().first(where: { $0.path == path.description }) else {
            throw WorkspaceError.splitNotFound(path.description)
        }

        return descriptor
    }

    public func updatingSplitRatio(at path: PaneLayoutPath, ratio: Double) throws -> PaneLayoutNode {
        try updatingSplitRatio(
            at: ArraySlice(path.components),
            fullPath: path,
            ratio: PaneSplitLayoutMetrics.clampedRatio(ratio)
        )
    }

    private func updatingSplitRatio(
        at path: ArraySlice<PaneLayoutBranch>,
        fullPath: PaneLayoutPath,
        ratio: Double
    ) throws -> PaneLayoutNode {
        switch self {
        case .leaf:
            throw WorkspaceError.splitNotFound(fullPath.description)
        case .split(let axis, let currentRatio, let primary, let secondary):
            guard let branch = path.first else {
                return .split(axis: axis, ratio: ratio, primary: primary, secondary: secondary)
            }

            switch branch {
            case .primary:
                let updatedPrimary = try primary.updatingSplitRatio(
                    at: path.dropFirst(),
                    fullPath: fullPath,
                    ratio: ratio
                )
                return .split(axis: axis, ratio: currentRatio, primary: updatedPrimary, secondary: secondary)
            case .secondary:
                let updatedSecondary = try secondary.updatingSplitRatio(
                    at: path.dropFirst(),
                    fullPath: fullPath,
                    ratio: ratio
                )
                return .split(axis: axis, ratio: currentRatio, primary: primary, secondary: updatedSecondary)
            }
        }
    }
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
    case invalidSplitPath(String)
    case splitNotFound(String)
    case invalidPane(String)

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .windowNotFound(let id):
            return "Window not found: \(id)"
        case .paneNotFound(let id):
            return "Pane not found: \(id)"
        case .invalidSplitPath(let path):
            return "Invalid split path: \(path)"
        case .splitNotFound(let path):
            return "Split not found: \(path)"
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
        let window = WorkspaceWindow(title: "Main", panes: [shell], layout: .leaf(shell.id))
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

    public func splitDescriptors(sessionID: String, windowID: String) throws -> [PaneSplitDescriptor] {
        guard let layout = try resolvedLayout(sessionID: sessionID, windowID: windowID) else {
            return []
        }

        return layout.splitDescriptors()
    }

    public func splitDescriptor(
        sessionID: String,
        windowID: String,
        splitPath: PaneLayoutPath
    ) throws -> PaneSplitDescriptor {
        guard let layout = try resolvedLayout(sessionID: sessionID, windowID: windowID) else {
            throw WorkspaceError.splitNotFound(splitPath.description)
        }

        return try layout.splitDescriptor(at: splitPath)
    }

    public func windowTitles(sessionID: String) throws -> [String] {
        try windowList(sessionID: sessionID).map(\.title)
    }

    public mutating func addSession(named name: String) -> WorkspaceSession {
        let session = WorkspaceSession(name: name, windows: [])
        sessions.append(session)
        return session
    }

    public mutating func updateSession(
        sessionID: String,
        using update: (inout WorkspaceSession) throws -> Void
    ) throws {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        try update(&sessions[sessionIndex])
    }

    public mutating func removeSession(sessionID: String) throws {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        sessions.remove(at: sessionIndex)
    }

    @discardableResult
    public mutating func addWindow(toSessionID sessionID: String, title: String) throws -> WorkspaceWindow {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let window = WorkspaceWindow(title: title, panes: [])
        sessions[sessionIndex].windows.append(window)
        return window
    }

    public mutating func updateWindow(
        sessionID: String,
        windowID: String,
        using update: (inout WorkspaceWindow) throws -> Void
    ) throws {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let windowIndex = try requireWindowIndex(sessionIndex: sessionIndex, windowID: windowID)
        try update(&sessions[sessionIndex].windows[windowIndex])
    }

    public mutating func removeWindow(sessionID: String, windowID: String) throws {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let windowIndex = try requireWindowIndex(sessionIndex: sessionIndex, windowID: windowID)
        sessions[sessionIndex].windows.remove(at: windowIndex)
    }

    @discardableResult
    public mutating func addPane(_ pane: WorkspacePane, toSessionID sessionID: String, windowID: String) throws -> WorkspacePane {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let windowIndex = try requireWindowIndex(sessionIndex: sessionIndex, windowID: windowID)
        sessions[sessionIndex].windows[windowIndex].panes.append(pane)
        if sessions[sessionIndex].windows[windowIndex].layout == nil,
           sessions[sessionIndex].windows[windowIndex].panes.count == 1 {
            sessions[sessionIndex].windows[windowIndex].layout = .leaf(pane.id)
        }
        return pane
    }

    public mutating func updatePane(
        sessionID: String,
        windowID: String,
        paneID: String,
        using update: (inout WorkspacePane) throws -> Void
    ) throws {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let windowIndex = try requireWindowIndex(sessionIndex: sessionIndex, windowID: windowID)
        let paneIndex = try requirePaneIndex(sessionIndex: sessionIndex, windowIndex: windowIndex, paneID: paneID)
        try update(&sessions[sessionIndex].windows[windowIndex].panes[paneIndex])
    }

    public mutating func removePane(sessionID: String, windowID: String, paneID: String) throws {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let windowIndex = try requireWindowIndex(sessionIndex: sessionIndex, windowID: windowID)
        let paneIndex = try requirePaneIndex(sessionIndex: sessionIndex, windowIndex: windowIndex, paneID: paneID)
        sessions[sessionIndex].windows[windowIndex].panes.remove(at: paneIndex)
        if let layout = sessions[sessionIndex].windows[windowIndex].layout {
            sessions[sessionIndex].windows[windowIndex].layout = removePaneFromLayout(layout, paneID: paneID)
        }
    }

    @discardableResult
    public mutating func updateSplitRatio(
        sessionID: String,
        windowID: String,
        splitPath: PaneLayoutPath,
        ratio: Double
    ) throws -> PaneSplitDescriptor {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let windowIndex = try requireWindowIndex(sessionIndex: sessionIndex, windowID: windowID)
        guard let currentLayout = resolvedLayout(for: sessions[sessionIndex].windows[windowIndex]) else {
            throw WorkspaceError.splitNotFound(splitPath.description)
        }

        let updatedLayout = try currentLayout.updatingSplitRatio(at: splitPath, ratio: ratio)
        sessions[sessionIndex].windows[windowIndex].layout = updatedLayout
        return try updatedLayout.splitDescriptor(at: splitPath)
    }

    @discardableResult
    public mutating func splitPane(
        sessionID: String,
        windowID: String,
        paneID: String?,
        axis: PaneSplitAxis,
        newPane: WorkspacePane
    ) throws -> WorkspacePane {
        let sessionIndex = try requireSessionIndex(sessionID: sessionID)
        let windowIndex = try requireWindowIndex(sessionIndex: sessionIndex, windowID: windowID)
        sessions[sessionIndex].windows[windowIndex].panes.append(newPane)

        let existingPanes = sessions[sessionIndex].windows[windowIndex].panes
        let fallbackPaneID = paneID
            ?? existingPanes.dropLast().last?.id
            ?? newPane.id
        let currentLayout = sessions[sessionIndex].windows[windowIndex].layout
            ?? legacyLayout(for: Array(existingPanes.dropLast()))

        sessions[sessionIndex].windows[windowIndex].layout = insertPaneIntoLayout(
            currentLayout,
            targetPaneID: fallbackPaneID,
            axis: axis,
            newPaneID: newPane.id
        )

        return newPane
    }

    private func windowList(sessionID: String) throws -> [WorkspaceWindow] {
        guard let session = session(withID: sessionID) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        return session.windows
    }

    private func requireSessionIndex(sessionID: String) throws -> Int {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        return sessionIndex
    }

    private func requireWindowIndex(sessionIndex: Int, windowID: String) throws -> Int {
        guard let windowIndex = sessions[sessionIndex].windows.firstIndex(where: { $0.id == windowID }) else {
            throw WorkspaceError.windowNotFound(windowID)
        }

        return windowIndex
    }

    private func requirePaneIndex(sessionIndex: Int, windowIndex: Int, paneID: String) throws -> Int {
        guard let paneIndex = sessions[sessionIndex].windows[windowIndex].panes.firstIndex(where: { $0.id == paneID }) else {
            throw WorkspaceError.paneNotFound(paneID)
        }

        return paneIndex
    }

    private func resolvedLayout(sessionID: String, windowID: String) throws -> PaneLayoutNode? {
        let window = try window(sessionID: sessionID, windowID: windowID)
        return resolvedLayout(for: window)
    }

    private func resolvedLayout(for window: WorkspaceWindow) -> PaneLayoutNode? {
        window.layout ?? legacyLayout(for: window.panes)
    }

    private func legacyLayout(for panes: [WorkspacePane]) -> PaneLayoutNode? {
        guard let firstPane = panes.first else {
            return nil
        }

        return panes.dropFirst().reduce(PaneLayoutNode.leaf(firstPane.id)) { partial, pane in
            .split(axis: .vertical, ratio: 0.5, primary: partial, secondary: .leaf(pane.id))
        }
    }

    private func insertPaneIntoLayout(
        _ layout: PaneLayoutNode?,
        targetPaneID: String,
        axis: PaneSplitAxis,
        newPaneID: String
    ) -> PaneLayoutNode {
        guard let layout else {
            return .leaf(newPaneID)
        }

        switch layout {
        case .leaf(let paneID):
            if paneID == targetPaneID {
                return .split(axis: axis, ratio: 0.5, primary: .leaf(paneID), secondary: .leaf(newPaneID))
            }
            return layout
        case .split(let splitAxis, let splitRatio, let primary, let secondary):
            let updatedPrimary = insertPaneIntoLayout(primary, targetPaneID: targetPaneID, axis: axis, newPaneID: newPaneID)
            if updatedPrimary != primary {
                return .split(axis: splitAxis, ratio: splitRatio, primary: updatedPrimary, secondary: secondary)
            }

            let updatedSecondary = insertPaneIntoLayout(secondary, targetPaneID: targetPaneID, axis: axis, newPaneID: newPaneID)
            return .split(axis: splitAxis, ratio: splitRatio, primary: primary, secondary: updatedSecondary)
        }
    }

    private func removePaneFromLayout(_ layout: PaneLayoutNode, paneID: String) -> PaneLayoutNode? {
        switch layout {
        case .leaf(let id):
            return id == paneID ? nil : layout
        case .split(let axis, let ratio, let primary, let secondary):
            let updatedPrimary = removePaneFromLayout(primary, paneID: paneID)
            let updatedSecondary = removePaneFromLayout(secondary, paneID: paneID)

            switch (updatedPrimary, updatedSecondary) {
            case (nil, nil):
                return nil
            case (let remaining?, nil), (nil, let remaining?):
                return remaining
            case (let primary?, let secondary?):
                return .split(axis: axis, ratio: ratio, primary: primary, secondary: secondary)
            }
        }
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
    public var layout: PaneLayoutNode?

    public init(id: String = UUID().uuidString, title: String, panes: [WorkspacePane] = [], layout: PaneLayoutNode? = nil) {
        self.id = id
        self.title = title
        self.panes = panes
        self.layout = layout
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

    public static func picker(title: String = "New Pane") -> WorkspacePane {
        WorkspacePane(
            title: title,
            kind: .picker
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

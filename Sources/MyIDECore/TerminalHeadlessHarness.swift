import AppKit
import Foundation
import SwiftTerm

@MainActor
public enum TerminalHeadlessHarness {
    public static func checkClickAndTyping(typedText: String) -> TerminalUITestResult {
        let result = TerminalInteractionHarness.checkClickAndTyping(typedText: typedText)
        return TerminalUITestResult(
            frontmostApplication: "Headless",
            editorValue: result.typedText,
            editorFocused: result.focusedAfterClick
        )
    }

    public static func checkLayout() -> TerminalUILayoutResult {
        let editor = TerminalCommandEditorView(transcript: "")
        let surfaceFrame = CGRect(x: 0, y: 0, width: 960, height: 640)
        editor.frame = surfaceFrame
        editor.layoutSubtreeIfNeeded()

        let editorFrame = editor.scrollView.frame
        return TerminalUILayoutResult(
            widthRatio: ratio(editorFrame.width, surfaceFrame.width),
            heightRatio: ratio(editorFrame.height, surfaceFrame.height)
        )
    }

    public static func runCommand(_ command: String, expecting expectedOutput: String) throws -> TerminalUITestResult {
        let terminal = HeadlessTerminal(options: .default) { _ in }
        terminal.terminal.resize(cols: 120, rows: 36)
        feed(Data("\(prompt)\(command)\r\n".utf8), into: terminal)
        let output = try commandOutput(for: command)
        feed(output, into: terminal)
        feed(Data("\r\n\(prompt)".utf8), into: terminal)

        let snapshot = terminalSnapshot(from: terminal)
        guard snapshot.contains(expectedOutput) else {
            throw TerminalUITestError.transcriptExpectationFailed(expectedOutput)
        }

        return TerminalUITestResult(
            frontmostApplication: "Headless",
            editorValue: snapshot,
            editorFocused: true
        )
    }

    public static func checkPaneChrome() -> PaneChromeTestResult {
        let chrome = PaneChromeConfiguration.minimal
        return PaneChromeTestResult(
            paneCount: 1,
            titleVisible: chrome.showsTitle,
            closeButtonVisible: chrome.showsCloseButton
        )
    }

    public static func checkEndOfTransmissionClosesPane() -> TerminalPaneLifecycleResult {
        let editor = TerminalCommandTextView(frame: .zero)
        var workspace = Workspace.starter()
        let sessionID = workspace.sessions[0].id
        let windowID = workspace.sessions[0].windows[0].id
        let paneID = workspace.sessions[0].windows[0].panes[0].id

        editor.onEndOfTransmission = {
            try? workspace.removePane(sessionID: sessionID, windowID: windowID, paneID: paneID)
        }

        if let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{04}",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ) {
            editor.keyDown(with: event)
        }

        let paneCount = workspace.sessions[0].windows[0].panes.count
        return TerminalPaneLifecycleResult(
            paneCount: paneCount,
            paneClosed: paneCount == 0
        )
    }

    public static func selectPreviewFile(_ selectedFilePath: String) -> FilePickerTestResult {
        var pane = WorkspacePane.markdownPreview(title: "Preview", filePath: "")
        pane.preview?.filePath = FileSelectionService.chooseFile(
            allowedContentTypes: [],
            automatedSelection: selectedFilePath
        ) ?? ""
        return FilePickerTestResult(selectedPath: pane.preview?.filePath ?? "")
    }

    public static func selectDiffFile(_ selectedFilePath: String) -> FilePickerTestResult {
        var pane = WorkspacePane.diff(title: "Diff", leftPath: "", rightPath: "")
        pane.diff?.leftPath = FileSelectionService.chooseFile(
            allowedContentTypes: [],
            automatedSelection: selectedFilePath
        ) ?? ""
        return FilePickerTestResult(selectedPath: pane.diff?.leftPath ?? "")
    }

    public static func checkSessionWindowSemantics() throws -> SessionWindowSemanticsResult {
        var workspace = Workspace.empty()
        let alpha = workspace.addSession(named: "Alpha")
        let alphaAppWindowCount = workspace.sessions.count
        let alphaSidebarWindowCount = try workspace.windowTitles(sessionID: alpha.id).count

        let alphaEditor = try workspace.addWindow(toSessionID: alpha.id, title: "Editor")
        let alphaSidebarTitles = try workspace.windowTitles(sessionID: alpha.id)

        let beta = workspace.addSession(named: "Beta")
        let betaAppWindowCount = workspace.sessions.count
        let betaSidebarWindowCount = try workspace.windowTitles(sessionID: beta.id).count
        let betaSidebarTitles = try workspace.windowTitles(sessionID: beta.id)

        return SessionWindowSemanticsResult(
            appWindowCountAfterFirstSession: alphaAppWindowCount,
            sidebarWindowCountAfterFirstSession: alphaSidebarWindowCount,
            sidebarWindowCountAfterAddingWindow: alphaSidebarTitles.count,
            sidebarWindowTitlesForFirstSession: alphaSidebarTitles,
            appWindowCountAfterSecondSession: betaAppWindowCount,
            sidebarWindowCountForSecondSession: betaSidebarWindowCount,
            sidebarWindowTitlesForSecondSession: betaSidebarTitles,
            firstAddedWindowTitle: alphaEditor.title
        )
    }

    public static func checkSwitchingToEmptyWindowKeepsMainPane() throws -> EmptyWindowSwitchResult {
        var workspace = Workspace.starter()
        let sessionID = workspace.sessions[0].id
        let mainWindowID = workspace.sessions[0].windows[0].id
        try workspace.addPane(
            .terminal(title: "Second", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath),
            toSessionID: sessionID,
            windowID: mainWindowID
        )
        try workspace.addPane(
            .terminal(title: "Third", provider: .ghostty, workingDirectory: FileManager.default.currentDirectoryPath),
            toSessionID: sessionID,
            windowID: mainWindowID
        )

        let mainPaneCountBefore = workspace.sessions[0].windows[0].panes.count

        _ = try workspace.addWindow(toSessionID: sessionID, title: "Scratch")

        let paneIDs = workspace.sessions[0].windows[0].panes.map(\.id)
        for paneID in paneIDs {
            let lifecycleController = TerminalPaneLifecycleController()
            lifecycleController.beginTearDown()
            if lifecycleController.shouldPropagateProcessTermination() {
                try workspace.removePane(sessionID: sessionID, windowID: mainWindowID, paneID: paneID)
            }
        }

        let mainWindow = try workspace.window(sessionID: sessionID, windowID: mainWindowID)
        let mainPaneCountAfter = mainWindow.panes.count

        return EmptyWindowSwitchResult(
            mainPaneCountBeforeSwitch: mainPaneCountBefore,
            mainPaneCountAfterReturn: mainPaneCountAfter,
            canReturnToMainWithoutError: mainPaneCountAfter > 0
        )
    }

    public static func checkMainWindowReselectionRegression() throws -> WindowReselectionRegressionResult {
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Main Session")
        let mainWindow = try workspace.addWindow(toSessionID: session.id, title: "Main")
        _ = try workspace.addPane(
            .terminal(title: "Shell 1", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath),
            toSessionID: session.id,
            windowID: mainWindow.id
        )
        _ = try workspace.addPane(
            .browser(title: "Docs", urlString: "https://swift.org"),
            toSessionID: session.id,
            windowID: mainWindow.id
        )
        _ = try workspace.addPane(
            .terminal(title: "Shell 2", provider: .ghostty, workingDirectory: FileManager.default.currentDirectoryPath),
            toSessionID: session.id,
            windowID: mainWindow.id
        )
        let scratchWindow = try workspace.addWindow(toSessionID: session.id, title: "Window 2")

        let mainPaneCountBefore = try workspace.window(sessionID: session.id, windowID: mainWindow.id).panes.count
        let mainPaneTitlesBefore = try workspace.window(sessionID: session.id, windowID: mainWindow.id).panes.map(\.title)

        let terminalPaneIDs = try workspace.window(sessionID: session.id, windowID: mainWindow.id).panes
            .filter { $0.kind == .terminal }
            .map(\.id)

        for paneID in terminalPaneIDs {
            let lifecycleController = TerminalPaneLifecycleController()
            lifecycleController.beginTearDown()
            if lifecycleController.shouldPropagateProcessTermination() {
                try workspace.removePane(sessionID: session.id, windowID: mainWindow.id, paneID: paneID)
            }
        }

        let scratchPaneCount = try workspace.window(sessionID: session.id, windowID: scratchWindow.id).panes.count
        let mainPaneCountAfter = try workspace.window(sessionID: session.id, windowID: mainWindow.id).panes.count
        let mainPaneTitlesAfter = try workspace.window(sessionID: session.id, windowID: mainWindow.id).panes.map(\.title)

        return WindowReselectionRegressionResult(
            mainPaneCountBeforeSwitch: mainPaneCountBefore,
            mainPaneCountAfterReturn: mainPaneCountAfter,
            scratchPaneCount: scratchPaneCount,
            mainPaneTitlesBeforeSwitch: mainPaneTitlesBefore,
            mainPaneTitlesAfterReturn: mainPaneTitlesAfter,
            canReturnToMainWithoutError: mainPaneCountAfter == mainPaneCountBefore && mainPaneTitlesAfter == mainPaneTitlesBefore
        )
    }

    private static func terminalSnapshot(from terminal: HeadlessTerminal) -> String {
        String(decoding: terminal.terminal.getBufferAsData(), as: UTF8.self)
    }

    private static func feed(_ data: Data, into terminal: HeadlessTerminal) {
        terminal.terminal.feed(buffer: [UInt8](data)[...])
    }

    private static func ratio(_ numerator: CGFloat, _ denominator: CGFloat) -> Double {
        guard denominator != 0 else {
            return 0
        }

        return Double(numerator / denominator)
    }

    private static func commandOutput(for command: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-fc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()
    }

    private static let shellPath = "/bin/zsh"
    private static let prompt = "MYIDE> "
}

public struct SessionWindowSemanticsResult: Codable, Sendable {
    public var appWindowCountAfterFirstSession: Int
    public var sidebarWindowCountAfterFirstSession: Int
    public var sidebarWindowCountAfterAddingWindow: Int
    public var sidebarWindowTitlesForFirstSession: [String]
    public var appWindowCountAfterSecondSession: Int
    public var sidebarWindowCountForSecondSession: Int
    public var sidebarWindowTitlesForSecondSession: [String]
    public var firstAddedWindowTitle: String

    public init(
        appWindowCountAfterFirstSession: Int,
        sidebarWindowCountAfterFirstSession: Int,
        sidebarWindowCountAfterAddingWindow: Int,
        sidebarWindowTitlesForFirstSession: [String],
        appWindowCountAfterSecondSession: Int,
        sidebarWindowCountForSecondSession: Int,
        sidebarWindowTitlesForSecondSession: [String],
        firstAddedWindowTitle: String
    ) {
        self.appWindowCountAfterFirstSession = appWindowCountAfterFirstSession
        self.sidebarWindowCountAfterFirstSession = sidebarWindowCountAfterFirstSession
        self.sidebarWindowCountAfterAddingWindow = sidebarWindowCountAfterAddingWindow
        self.sidebarWindowTitlesForFirstSession = sidebarWindowTitlesForFirstSession
        self.appWindowCountAfterSecondSession = appWindowCountAfterSecondSession
        self.sidebarWindowCountForSecondSession = sidebarWindowCountForSecondSession
        self.sidebarWindowTitlesForSecondSession = sidebarWindowTitlesForSecondSession
        self.firstAddedWindowTitle = firstAddedWindowTitle
    }
}

public struct EmptyWindowSwitchResult: Codable, Sendable {
    public var mainPaneCountBeforeSwitch: Int
    public var mainPaneCountAfterReturn: Int
    public var canReturnToMainWithoutError: Bool

    public init(
        mainPaneCountBeforeSwitch: Int,
        mainPaneCountAfterReturn: Int,
        canReturnToMainWithoutError: Bool
    ) {
        self.mainPaneCountBeforeSwitch = mainPaneCountBeforeSwitch
        self.mainPaneCountAfterReturn = mainPaneCountAfterReturn
        self.canReturnToMainWithoutError = canReturnToMainWithoutError
    }
}

public struct WindowReselectionRegressionResult: Codable, Sendable {
    public var mainPaneCountBeforeSwitch: Int
    public var mainPaneCountAfterReturn: Int
    public var scratchPaneCount: Int
    public var mainPaneTitlesBeforeSwitch: [String]
    public var mainPaneTitlesAfterReturn: [String]
    public var canReturnToMainWithoutError: Bool

    public init(
        mainPaneCountBeforeSwitch: Int,
        mainPaneCountAfterReturn: Int,
        scratchPaneCount: Int,
        mainPaneTitlesBeforeSwitch: [String],
        mainPaneTitlesAfterReturn: [String],
        canReturnToMainWithoutError: Bool
    ) {
        self.mainPaneCountBeforeSwitch = mainPaneCountBeforeSwitch
        self.mainPaneCountAfterReturn = mainPaneCountAfterReturn
        self.scratchPaneCount = scratchPaneCount
        self.mainPaneTitlesBeforeSwitch = mainPaneTitlesBeforeSwitch
        self.mainPaneTitlesAfterReturn = mainPaneTitlesAfterReturn
        self.canReturnToMainWithoutError = canReturnToMainWithoutError
    }
}

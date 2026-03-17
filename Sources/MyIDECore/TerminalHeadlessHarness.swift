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

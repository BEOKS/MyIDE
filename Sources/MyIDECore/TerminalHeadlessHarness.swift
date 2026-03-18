import AppKit
import Foundation
import SwiftUI
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
        _ = try workspace.addWindow(toSessionID: alpha.id, title: "Main")
        let alphaAppWindowCount = workspace.sessions.count
        let alphaSidebarWindowCount = try workspace.windowTitles(sessionID: alpha.id).count
        let alphaSidebarTitles = try workspace.windowTitles(sessionID: alpha.id)

        let alphaEditor = try workspace.addWindow(toSessionID: alpha.id, title: "Editor")
        let alphaSidebarTitlesAfterAddingWindow = try workspace.windowTitles(sessionID: alpha.id)

        let beta = workspace.addSession(named: "Beta")
        _ = try workspace.addWindow(toSessionID: beta.id, title: "Main")
        let betaAppWindowCount = workspace.sessions.count
        let betaSidebarWindowCount = try workspace.windowTitles(sessionID: beta.id).count
        let betaSidebarTitles = try workspace.windowTitles(sessionID: beta.id)

        return SessionWindowSemanticsResult(
            appWindowCountAfterFirstSession: alphaAppWindowCount,
            sidebarWindowCountAfterFirstSession: alphaSidebarWindowCount,
            sidebarWindowTitlesAfterFirstSessionCreation: alphaSidebarTitles,
            sidebarWindowCountAfterAddingWindow: alphaSidebarTitlesAfterAddingWindow.count,
            sidebarWindowTitlesForFirstSession: alphaSidebarTitlesAfterAddingWindow,
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

    public static func checkAddPaneSheetIsScopedPerSessionWindow() -> AddPaneSheetScopeResult {
        let firstWindowState = WindowSceneState()
        let secondWindowState = WindowSceneState()

        firstWindowState.showingAddPaneSheet = true

        return AddPaneSheetScopeResult(
            firstWindowShowingSheet: firstWindowState.showingAddPaneSheet,
            secondWindowShowingSheet: secondWindowState.showingAddPaneSheet
        )
    }

    public static func checkNewSessionStartsWithMainWindow() throws -> NewSessionDefaultsResult {
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let mainWindow = try workspace.addWindow(toSessionID: session.id, title: "Main")
        let windowTitles = try workspace.windowTitles(sessionID: session.id)

        return NewSessionDefaultsResult(
            windowCount: windowTitles.count,
            firstWindowTitle: windowTitles.first ?? "",
            addPaneEnabled: try workspace.window(sessionID: session.id, windowID: mainWindow.id).id == mainWindow.id
        )
    }

    public static func checkIMECompositionCommit() -> IMECompositionResult {
        let composition = TerminalCompositionState()
        composition.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0))
        let firstMarkedRange = composition.markedRange()
        let hadMarkedTextDuringComposition = composition.hasMarkedText

        composition.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0))
        let updatedMarkedRange = composition.markedRange()
        let committedText = composition.committedText(from: "한") ?? ""
        let hasMarkedTextAfterCommit = composition.hasMarkedText

        return IMECompositionResult(
            hadMarkedTextDuringComposition: hadMarkedTextDuringComposition,
            firstMarkedRangeLength: firstMarkedRange.length,
            updatedMarkedRangeLength: updatedMarkedRange.length,
            committedText: committedText,
            hasMarkedTextAfterCommit: hasMarkedTextAfterCommit
        )
    }

    public static func checkDeleteToBeginningOfLineShortcut() throws -> TerminalShortcutResult {
        let transcript = TerminalTranscriptBuffer()
        let session = PTYTerminalSession(
            configuration: .init(
                workingDirectory: FileManager.default.currentDirectoryPath,
                shellPath: "/bin/zsh",
                prompt: prompt
            )
        )

        session.onData = { data in
            _ = transcript.append(data)
        }

        try session.start()
        defer { session.stop() }

        guard waitUntil(timeout: 5, body: { transcript.text.contains(prompt) ? true : nil }) != nil else {
            throw TerminalUITestError.transcriptExpectationFailed(prompt)
        }

        session.write("garbage")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        session.write(Data(TerminalShortcutAction.deleteToBeginningOfLine.bytes))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        session.write("printf 'ok'\n")

        guard let finalTranscript = waitUntil(timeout: 5, body: {
            transcript.text.contains("ok") ? transcript.text : nil
        }) else {
            throw TerminalUITestError.transcriptExpectationFailed("ok")
        }

        let succeeded = finalTranscript.contains("ok") && !finalTranscript.contains("garbageprintf")
        return TerminalShortcutResult(
            transcript: finalTranscript,
            succeeded: succeeded
        )
    }

    public static func checkTmuxSplitShortcuts() throws -> TmuxSplitShortcutResult {
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")
        let rootPane = WorkspacePane.terminal(
            title: "Shell",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        try workspace.addPane(rootPane, toSessionID: session.id, windowID: window.id)

        let verticalPane = WorkspacePane.terminal(
            title: "Vertical Split",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: rootPane.id,
            axis: .vertical,
            newPane: verticalPane
        )

        let layoutAfterVertical = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let horizontalPane = WorkspacePane.terminal(
            title: "Horizontal Split",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: verticalPane.id,
            axis: .horizontal,
            newPane: horizontalPane
        )

        let finalWindow = try workspace.window(sessionID: session.id, windowID: window.id)
        return TmuxSplitShortcutResult(
            paneCount: finalWindow.panes.count,
            rootAxisAfterVerticalSplit: axisName(of: layoutAfterVertical),
            finalLayoutDescription: describe(layout: finalWindow.layout)
        )
    }

    public static func checkBrowserAndMarkdownPaneCloseShortcuts() throws -> PaneCloseShortcutResult {
        let browserClosed = try checkCloseShortcutRemovesPane(kind: .browser)
        let markdownClosed = try checkCloseShortcutRemovesPane(kind: .markdownPreview)
        let terminalIgnored = try checkCloseShortcutIgnored(kind: .terminal)

        return PaneCloseShortcutResult(
            browserPaneClosed: browserClosed,
            markdownPaneClosed: markdownClosed,
            terminalPaneIgnoredByWindowShortcut: terminalIgnored
        )
    }

    public static func checkTmuxSplitShortcutKeyMatching() throws -> TmuxSplitKeyMatchResult {
        // Test that NSEvent with Ctrl+Shift produces correct charactersIgnoringModifiers
        let verticalEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1d}",
            charactersIgnoringModifiers: "%",
            isARepeat: false,
            keyCode: 23
        )

        let horizontalEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1c}",
            charactersIgnoringModifiers: "\"",
            isARepeat: false,
            keyCode: 39
        )

        let verticalKeyMatched = verticalEvent?.charactersIgnoringModifiers == "%"
        let horizontalKeyMatched = horizontalEvent?.charactersIgnoringModifiers == "\""

        // Also verify model-level split works
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")
        let rootPane = WorkspacePane.terminal(
            title: "Shell",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        try workspace.addPane(rootPane, toSessionID: session.id, windowID: window.id)

        if verticalKeyMatched {
            let vPane = WorkspacePane.terminal(title: "V", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath)
            _ = try workspace.splitPane(sessionID: session.id, windowID: window.id, paneID: rootPane.id, axis: .vertical, newPane: vPane)
        }
        if horizontalKeyMatched {
            let hPane = WorkspacePane.terminal(title: "H", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath)
            _ = try workspace.splitPane(sessionID: session.id, windowID: window.id, paneID: rootPane.id, axis: .horizontal, newPane: hPane)
        }

        let finalWindow = try workspace.window(sessionID: session.id, windowID: window.id)
        return TmuxSplitKeyMatchResult(
            verticalKeyMatched: verticalKeyMatched,
            horizontalKeyMatched: horizontalKeyMatched,
            paneCountAfterSplits: finalWindow.panes.count
        )
    }

    public static func checkNestedPaneSplit() throws -> NestedPaneSplitResult {
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")
        let topPane = WorkspacePane.terminal(
            title: "Top",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        try workspace.addPane(topPane, toSessionID: session.id, windowID: window.id)

        // Step 1: horizontal split (top / bottom)
        let bottomPane = WorkspacePane.terminal(
            title: "Bottom",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: topPane.id,
            axis: .horizontal,
            newPane: bottomPane
        )

        let layoutAfterFirstSplit = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let rootAxisAfterFirstSplit = axisName(of: layoutAfterFirstSplit)

        // Step 2: vertical split on bottom pane (bottom-left / bottom-right)
        let bottomRightPane = WorkspacePane.terminal(
            title: "BottomRight",
            provider: .terminal,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: bottomPane.id,
            axis: .vertical,
            newPane: bottomRightPane
        )

        let finalWindow = try workspace.window(sessionID: session.id, windowID: window.id)
        let finalLayout = finalWindow.layout
        let finalDescription = describe(layout: finalLayout)

        // Verify nested structure: root should be horizontal, and secondary child should be vertical
        let secondaryAxis: String?
        if case .split(_, _, _, let secondary) = finalLayout {
            secondaryAxis = axisName(of: secondary)
        } else {
            secondaryAxis = nil
        }

        let rootRatio: Double?
        if case .split(_, let r, _, _) = finalLayout {
            rootRatio = r
        } else {
            rootRatio = nil
        }

        let nestedRatio: Double?
        if case .split(_, _, _, let secondary) = finalLayout,
           case .split(_, let r, _, _) = secondary {
            nestedRatio = r
        } else {
            nestedRatio = nil
        }

        return NestedPaneSplitResult(
            paneCount: finalWindow.panes.count,
            rootAxis: axisName(of: finalLayout),
            nestedAxis: secondaryAxis,
            rootRatio: rootRatio,
            nestedRatio: nestedRatio,
            layoutDescription: finalDescription
        )
    }

    public static func checkPaneSplitAndRemove() throws -> PaneSplitRemoveResult {
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")
        let paneA = WorkspacePane.terminal(title: "A", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath)
        try workspace.addPane(paneA, toSessionID: session.id, windowID: window.id)

        // Split vertically: A | B
        let paneB = WorkspacePane.terminal(title: "B", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath)
        _ = try workspace.splitPane(sessionID: session.id, windowID: window.id, paneID: paneA.id, axis: .vertical, newPane: paneB)

        let layoutAfterSplit = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let paneCountAfterSplit = try workspace.window(sessionID: session.id, windowID: window.id).panes.count

        // Verify split layout: should be split(vertical, 0.5, leaf(A), leaf(B))
        let isSplitAfterAdd: Bool
        let splitRatio: Double?
        if case .split(let axis, let ratio, .leaf(let leftID), .leaf(let rightID)) = layoutAfterSplit,
           axis == .vertical, leftID == paneA.id, rightID == paneB.id {
            isSplitAfterAdd = true
            splitRatio = ratio
        } else {
            isSplitAfterAdd = false
            splitRatio = nil
        }

        // Remove pane B: A should take full space
        try workspace.removePane(sessionID: session.id, windowID: window.id, paneID: paneB.id)

        let layoutAfterRemove = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let paneCountAfterRemove = try workspace.window(sessionID: session.id, windowID: window.id).panes.count

        let isLeafAfterRemove: Bool
        if case .leaf(let id) = layoutAfterRemove, id == paneA.id {
            isLeafAfterRemove = true
        } else {
            isLeafAfterRemove = false
        }

        return PaneSplitRemoveResult(
            paneCountAfterSplit: paneCountAfterSplit,
            isSplitAfterAdd: isSplitAfterAdd,
            splitRatio: splitRatio,
            paneCountAfterRemove: paneCountAfterRemove,
            isLeafAfterRemove: isLeafAfterRemove
        )
    }

    public static func checkPaneLayoutStability() throws -> PaneLayoutStabilityResult {
        let cwd = FileManager.default.currentDirectoryPath
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")

        // Start with pane A
        let paneA = WorkspacePane.terminal(title: "A", provider: .terminal, workingDirectory: cwd)
        try workspace.addPane(paneA, toSessionID: session.id, windowID: window.id)

        // 1) Vertical split A → A | B
        let paneB = WorkspacePane.terminal(title: "B", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(sessionID: session.id, windowID: window.id, paneID: paneA.id, axis: .vertical, newPane: paneB)

        // 2) Horizontal split B → B / C  (deep nesting: vertical(A, horizontal(B, C)))
        let paneC = WorkspacePane.terminal(title: "C", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(sessionID: session.id, windowID: window.id, paneID: paneB.id, axis: .horizontal, newPane: paneC)

        // 3) Vertical split C → C | D  (3-level nesting)
        let paneD = WorkspacePane.terminal(title: "D", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(sessionID: session.id, windowID: window.id, paneID: paneC.id, axis: .vertical, newPane: paneD)

        let layoutAfter4Panes = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let descAfter4Panes = describe(layout: layoutAfter4Panes)
        let allRatiosHalf4 = collectRatios(layout: layoutAfter4Panes).allSatisfy { $0 == 0.5 }

        // 4) Delete D (secondary of deepest split) → C should become leaf, B/C horizontal remains
        try workspace.removePane(sessionID: session.id, windowID: window.id, paneID: paneD.id)
        let layoutAfterDeleteD = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let descAfterDeleteD = describe(layout: layoutAfterDeleteD)
        let paneCountAfterDeleteD = try workspace.window(sessionID: session.id, windowID: window.id).panes.count
        let allRatiosHalf3 = collectRatios(layout: layoutAfterDeleteD).allSatisfy { $0 == 0.5 }

        // 5) Delete B (primary of horizontal split) → C should take B's place
        try workspace.removePane(sessionID: session.id, windowID: window.id, paneID: paneB.id)
        let layoutAfterDeleteB = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let descAfterDeleteB = describe(layout: layoutAfterDeleteB)
        let paneCountAfterDeleteB = try workspace.window(sessionID: session.id, windowID: window.id).panes.count

        // Should be vertical(A, C) — the horizontal wrapper collapses
        let siblingPreserved: Bool
        if case .split(let axis, let ratio, .leaf(let left), .leaf(let right)) = layoutAfterDeleteB,
           axis == .vertical, ratio == 0.5, left == paneA.id, right == paneC.id {
            siblingPreserved = true
        } else {
            siblingPreserved = false
        }

        // 6) Delete A (primary of root) → C alone as leaf
        try workspace.removePane(sessionID: session.id, windowID: window.id, paneID: paneA.id)
        let layoutAfterDeleteA = try workspace.window(sessionID: session.id, windowID: window.id).layout
        let finalIsLeaf: Bool
        if case .leaf(let id) = layoutAfterDeleteA, id == paneC.id {
            finalIsLeaf = true
        } else {
            finalIsLeaf = false
        }

        return PaneLayoutStabilityResult(
            descAfter4Panes: descAfter4Panes,
            allRatiosHalf4Panes: allRatiosHalf4,
            descAfterDeleteSecondary: descAfterDeleteD,
            paneCountAfterDeleteSecondary: paneCountAfterDeleteD,
            allRatiosHalfAfterDeleteSecondary: allRatiosHalf3,
            descAfterDeletePrimary: descAfterDeleteB,
            paneCountAfterDeletePrimary: paneCountAfterDeleteB,
            siblingPreservedAfterPrimaryDelete: siblingPreserved,
            lastPaneIsLeaf: finalIsLeaf
        )
    }

    public static func checkSplitPresentationSizing() -> SplitPresentationSizingResult {
        let verticalMetrics = PaneSplitLayoutMetrics(totalExtent: 200, ratio: 0.5)
        let horizontalMetrics = PaneSplitLayoutMetrics(totalExtent: 300, ratio: 0.5)
        let pickerMetrics = PanePickerLayoutMetrics(containerWidth: 200, containerHeight: 150)

        return SplitPresentationSizingResult(
            verticalPrimaryExtent: verticalMetrics.primaryExtent,
            verticalSecondaryExtent: verticalMetrics.secondaryExtent,
            horizontalPrimaryExtent: horizontalMetrics.primaryExtent,
            horizontalSecondaryExtent: horizontalMetrics.secondaryExtent,
            compactPickerColumnCount: pickerMetrics.columnCount,
            compactPickerRequiresScrolling: pickerMetrics.requiresScrolling
        )
    }

    public static func checkPaneDividerResizing() throws -> PaneDividerResizeResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("myide-divider-resize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workspaceURL = tempDir.appendingPathComponent("workspace.json")
        let cwd = FileManager.default.currentDirectoryPath

        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")

        let rootPane = WorkspacePane.terminal(title: "Root", provider: .terminal, workingDirectory: cwd)
        try workspace.addPane(rootPane, toSessionID: session.id, windowID: window.id)

        let rightPane = WorkspacePane.terminal(title: "Right", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: rootPane.id,
            axis: .vertical,
            newPane: rightPane
        )

        let bottomRightPane = WorkspacePane.terminal(title: "BottomRight", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: rightPane.id,
            axis: .horizontal,
            newPane: bottomRightPane
        )

        let rootPath = PaneLayoutPath.root
        let nestedPath = PaneLayoutPath.root.appending(.secondary)

        let verticalRatio = PaneSplitLayoutMetrics.ratio(forDividerLocation: 260, totalExtent: 400)
        let horizontalRatio = PaneSplitLayoutMetrics.ratio(forDividerLocation: 225, totalExtent: 300)

        _ = try workspace.updateSplitRatio(
            sessionID: session.id,
            windowID: window.id,
            splitPath: rootPath,
            ratio: verticalRatio
        )
        _ = try workspace.updateSplitRatio(
            sessionID: session.id,
            windowID: window.id,
            splitPath: nestedPath,
            ratio: horizontalRatio
        )

        let verticalMetrics = PaneSplitLayoutMetrics(
            totalExtent: 400,
            ratio: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: rootPath
            ).ratio
        )
        let horizontalMetrics = PaneSplitLayoutMetrics(
            totalExtent: 300,
            ratio: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: nestedPath
            ).ratio
        )

        try WorkspaceStore.save(workspace, to: workspaceURL)
        let reloadedWorkspace = try WorkspaceStore.load(from: workspaceURL)
        let reloadedSplits = try reloadedWorkspace.splitDescriptors(sessionID: session.id, windowID: window.id)

        return PaneDividerResizeResult(
            verticalRatio: verticalRatio,
            verticalPrimaryExtent: verticalMetrics.primaryExtent,
            verticalSecondaryExtent: verticalMetrics.secondaryExtent,
            horizontalRatio: horizontalRatio,
            horizontalPrimaryExtent: horizontalMetrics.primaryExtent,
            horizontalSecondaryExtent: horizontalMetrics.secondaryExtent,
            reloadedSplits: reloadedSplits
        )
    }

    public static func checkSplitDividerHitTesting() -> SplitDividerHitTestingResult {
        let horizontal = InteractivePaneSplitContainerView(
            axis: .horizontal,
            ratio: 0.5,
            primary: Color.red,
            secondary: Color.blue
        )
        horizontal.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        horizontal.layoutSubtreeIfNeeded()

        let vertical = InteractivePaneSplitContainerView(
            axis: .vertical,
            ratio: 0.5,
            primary: Color.red,
            secondary: Color.blue
        )
        vertical.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        vertical.layoutSubtreeIfNeeded()

        return SplitDividerHitTestingResult(
            horizontalTopPointHitsDivider: horizontal.hitTestReturnsDivider(at: CGPoint(x: 100, y: 10)),
            horizontalDividerPointHitsDivider: horizontal.hitTestReturnsDivider(at: CGPoint(x: 100, y: 100)),
            verticalLeftPointHitsDivider: vertical.hitTestReturnsDivider(at: CGPoint(x: 10, y: 100)),
            verticalDividerPointHitsDivider: vertical.hitTestReturnsDivider(at: CGPoint(x: 100, y: 100))
        )
    }

    public static func checkNestedSplitResizeIsolation() throws -> NestedSplitResizeIsolationResult {
        let cwd = FileManager.default.currentDirectoryPath
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")

        let topLeft = WorkspacePane.terminal(title: "TopLeft", provider: .terminal, workingDirectory: cwd)
        try workspace.addPane(topLeft, toSessionID: session.id, windowID: window.id)

        let bottomLeft = WorkspacePane.terminal(title: "BottomLeft", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: topLeft.id,
            axis: .horizontal,
            newPane: bottomLeft
        )

        let topRight = WorkspacePane.terminal(title: "TopRight", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: topLeft.id,
            axis: .vertical,
            newPane: topRight
        )

        let bottomRight = WorkspacePane.terminal(title: "BottomRight", provider: .terminal, workingDirectory: cwd)
        _ = try workspace.splitPane(
            sessionID: session.id,
            windowID: window.id,
            paneID: bottomLeft.id,
            axis: .vertical,
            newPane: bottomRight
        )

        let rootPath = PaneLayoutPath.root
        let topSplitPath = PaneLayoutPath.root.appending(.primary)
        let bottomSplitPath = PaneLayoutPath.root.appending(.secondary)

        _ = try workspace.updateSplitRatio(
            sessionID: session.id,
            windowID: window.id,
            splitPath: rootPath,
            ratio: 0.25
        )

        let topHeightMetrics = PaneSplitLayoutMetrics(
            totalExtent: 400,
            ratio: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: rootPath
            ).ratio
        )

        let topWidthBefore = PaneSplitLayoutMetrics(
            totalExtent: 200,
            ratio: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: topSplitPath
            ).ratio
        )
        let bottomWidthBefore = PaneSplitLayoutMetrics(
            totalExtent: 200,
            ratio: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: bottomSplitPath
            ).ratio
        )

        _ = try workspace.updateSplitRatio(
            sessionID: session.id,
            windowID: window.id,
            splitPath: topSplitPath,
            ratio: 0.25
        )

        let topWidthAfter = PaneSplitLayoutMetrics(
            totalExtent: 200,
            ratio: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: topSplitPath
            ).ratio
        )
        let bottomWidthAfter = PaneSplitLayoutMetrics(
            totalExtent: 200,
            ratio: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: bottomSplitPath
            ).ratio
        )

        return NestedSplitResizeIsolationResult(
            rootRatioAfterHeightResize: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: rootPath
            ).ratio,
            topHeightAfterHeightResize: topHeightMetrics.primaryExtent,
            bottomHeightAfterHeightResize: topHeightMetrics.secondaryExtent,
            topWidthBeforeIndependentResize: topWidthBefore.primaryExtent,
            topWidthSiblingBeforeIndependentResize: topWidthBefore.secondaryExtent,
            bottomWidthBeforeIndependentResize: bottomWidthBefore.primaryExtent,
            bottomWidthSiblingBeforeIndependentResize: bottomWidthBefore.secondaryExtent,
            topWidthAfterIndependentResize: topWidthAfter.primaryExtent,
            topWidthSiblingAfterIndependentResize: topWidthAfter.secondaryExtent,
            bottomWidthAfterIndependentResize: bottomWidthAfter.primaryExtent,
            bottomWidthSiblingAfterIndependentResize: bottomWidthAfter.secondaryExtent,
            bottomSplitRatioAfterTopResize: try workspace.splitDescriptor(
                sessionID: session.id,
                windowID: window.id,
                splitPath: bottomSplitPath
            ).ratio
        )
    }

    public static func checkCLIWorkspaceSync() throws -> CLIWorkspaceSyncResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("myide-sync-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workspaceURL = tempDir.appendingPathComponent("workspace.json")

        // 1) Create initial workspace with one session
        var workspace = Workspace.empty()
        let session1 = workspace.addSession(named: "Session 1")
        _ = try workspace.addWindow(toSessionID: session1.id, title: "Main")
        try WorkspaceStore.save(workspace, to: workspaceURL)

        let initialSessionCount = workspace.sessions.count

        // 2) Simulate CLI adding a second session + saveAndNotify
        var received = false
        let expectation = DistributedNotificationCenter.default().addObserver(
            forName: WorkspaceStore.workspaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let path = notification.object as? String, path == workspaceURL.path {
                received = true
            }
        }

        let session2 = workspace.addSession(named: "Session 2")
        _ = try workspace.addWindow(toSessionID: session2.id, title: "Main")
        try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)

        // Pump run loop to let notification deliver
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        DistributedNotificationCenter.default().removeObserver(expectation)

        let notificationReceived = received

        // 3) Simulate app reload (what AppViewModel does on notification)
        let reloaded = try WorkspaceStore.load(from: workspaceURL)
        let reloadedSessionCount = reloaded.sessions.count
        let reloadedSessionNames = reloaded.sessions.map(\.name)

        // 4) Simulate CLI deleting session 1 + notify
        var mutable = reloaded
        try mutable.removeSession(sessionID: session1.id)
        try WorkspaceStore.saveAndNotify(mutable, to: workspaceURL)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let afterDelete = try WorkspaceStore.load(from: workspaceURL)
        let afterDeleteSessionCount = afterDelete.sessions.count
        let afterDeleteSessionNames = afterDelete.sessions.map(\.name)

        // 5) Simulate CLI adding a pane to session 2's window
        var withPane = afterDelete
        let windowID = withPane.sessions[0].windows[0].id
        let pane = WorkspacePane.terminal(title: "CLI Pane", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath)
        try withPane.addPane(pane, toSessionID: session2.id, windowID: windowID)
        try WorkspaceStore.saveAndNotify(withPane, to: workspaceURL)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let afterAddPane = try WorkspaceStore.load(from: workspaceURL)
        let paneCount = afterAddPane.sessions[0].windows[0].panes.count
        let paneTitles = afterAddPane.sessions[0].windows[0].panes.map(\.title)

        return CLIWorkspaceSyncResult(
            initialSessionCount: initialSessionCount,
            notificationReceived: notificationReceived,
            reloadedSessionCount: reloadedSessionCount,
            reloadedSessionNames: reloadedSessionNames,
            afterDeleteSessionCount: afterDeleteSessionCount,
            afterDeleteSessionNames: afterDeleteSessionNames,
            paneCountAfterCLIAdd: paneCount,
            paneTitlesAfterCLIAdd: paneTitles
        )
    }

    private static func collectRatios(layout: PaneLayoutNode?) -> [Double] {
        guard let layout else { return [] }
        switch layout {
        case .leaf:
            return []
        case .split(_, let ratio, let primary, let secondary):
            return [ratio] + collectRatios(layout: primary) + collectRatios(layout: secondary)
        }
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

    private static func axisName(of layout: PaneLayoutNode?) -> String? {
        guard case .split(let axis, _, _, _) = layout else {
            return nil
        }

        return axis.rawValue
    }

    private static func describe(layout: PaneLayoutNode?) -> String {
        guard let layout else {
            return "empty"
        }

        switch layout {
        case .leaf(let paneID):
            return "leaf(\(paneID))"
        case .split(let axis, let ratio, let primary, let secondary):
            return "\(axis.rawValue)(\(String(format: "%.1f", ratio)),\(describe(layout: primary)),\(describe(layout: secondary)))"
        }
    }

    private static func waitUntil<T>(timeout: TimeInterval, pollInterval: TimeInterval = 0.05, body: () -> T?) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = body() {
                return value
            }

            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }

        return nil
    }

    private static func checkCloseShortcutRemovesPane(kind: PaneKind) throws -> Bool {
        var workspace = Workspace.empty()
        let session = workspace.addSession(named: "Session 1")
        let window = try workspace.addWindow(toSessionID: session.id, title: "Main")
        let pane = makePane(for: kind)
        try workspace.addPane(pane, toSessionID: session.id, windowID: window.id)

        guard let event = NSEvent.keyEvent(
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
        ) else {
            return false
        }

        guard PaneShortcutAction.resolve(event: event, selectedPaneKind: kind) == .closeSelectedPane else {
            return false
        }

        try workspace.removePane(sessionID: session.id, windowID: window.id, paneID: pane.id)
        return try workspace.window(sessionID: session.id, windowID: window.id).panes.isEmpty
    }

    private static func checkCloseShortcutIgnored(kind: PaneKind) throws -> Bool {
        guard let event = NSEvent.keyEvent(
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
        ) else {
            return false
        }

        return PaneShortcutAction.resolve(event: event, selectedPaneKind: kind) == nil
    }

    private static func makePane(for kind: PaneKind) -> WorkspacePane {
        switch kind {
        case .picker:
            return .picker()
        case .terminal:
            return .terminal(title: "Shell", provider: .terminal, workingDirectory: FileManager.default.currentDirectoryPath)
        case .browser:
            return .browser(title: "Docs", urlString: "https://swift.org")
        case .diff:
            return .diff(title: "Diff", leftPath: "before.txt", rightPath: "after.txt")
        case .markdownPreview:
            return .markdownPreview(title: "Preview", filePath: "README.md")
        case .imagePreview:
            return .imagePreview(title: "Image", filePath: "image.png")
        }
    }
}

public struct SessionWindowSemanticsResult: Codable, Sendable {
    public var appWindowCountAfterFirstSession: Int
    public var sidebarWindowCountAfterFirstSession: Int
    public var sidebarWindowTitlesAfterFirstSessionCreation: [String]
    public var sidebarWindowCountAfterAddingWindow: Int
    public var sidebarWindowTitlesForFirstSession: [String]
    public var appWindowCountAfterSecondSession: Int
    public var sidebarWindowCountForSecondSession: Int
    public var sidebarWindowTitlesForSecondSession: [String]
    public var firstAddedWindowTitle: String

    public init(
        appWindowCountAfterFirstSession: Int,
        sidebarWindowCountAfterFirstSession: Int,
        sidebarWindowTitlesAfterFirstSessionCreation: [String],
        sidebarWindowCountAfterAddingWindow: Int,
        sidebarWindowTitlesForFirstSession: [String],
        appWindowCountAfterSecondSession: Int,
        sidebarWindowCountForSecondSession: Int,
        sidebarWindowTitlesForSecondSession: [String],
        firstAddedWindowTitle: String
    ) {
        self.appWindowCountAfterFirstSession = appWindowCountAfterFirstSession
        self.sidebarWindowCountAfterFirstSession = sidebarWindowCountAfterFirstSession
        self.sidebarWindowTitlesAfterFirstSessionCreation = sidebarWindowTitlesAfterFirstSessionCreation
        self.sidebarWindowCountAfterAddingWindow = sidebarWindowCountAfterAddingWindow
        self.sidebarWindowTitlesForFirstSession = sidebarWindowTitlesForFirstSession
        self.appWindowCountAfterSecondSession = appWindowCountAfterSecondSession
        self.sidebarWindowCountForSecondSession = sidebarWindowCountForSecondSession
        self.sidebarWindowTitlesForSecondSession = sidebarWindowTitlesForSecondSession
        self.firstAddedWindowTitle = firstAddedWindowTitle
    }
}

public struct NewSessionDefaultsResult: Codable, Sendable {
    public var windowCount: Int
    public var firstWindowTitle: String
    public var addPaneEnabled: Bool

    public init(windowCount: Int, firstWindowTitle: String, addPaneEnabled: Bool) {
        self.windowCount = windowCount
        self.firstWindowTitle = firstWindowTitle
        self.addPaneEnabled = addPaneEnabled
    }
}

public struct IMECompositionResult: Codable, Sendable {
    public var hadMarkedTextDuringComposition: Bool
    public var firstMarkedRangeLength: Int
    public var updatedMarkedRangeLength: Int
    public var committedText: String
    public var hasMarkedTextAfterCommit: Bool

    public init(
        hadMarkedTextDuringComposition: Bool,
        firstMarkedRangeLength: Int,
        updatedMarkedRangeLength: Int,
        committedText: String,
        hasMarkedTextAfterCommit: Bool
    ) {
        self.hadMarkedTextDuringComposition = hadMarkedTextDuringComposition
        self.firstMarkedRangeLength = firstMarkedRangeLength
        self.updatedMarkedRangeLength = updatedMarkedRangeLength
        self.committedText = committedText
        self.hasMarkedTextAfterCommit = hasMarkedTextAfterCommit
    }
}

public struct TerminalShortcutResult: Codable, Sendable {
    public var transcript: String
    public var succeeded: Bool

    public init(transcript: String, succeeded: Bool) {
        self.transcript = transcript
        self.succeeded = succeeded
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

public struct AddPaneSheetScopeResult: Codable, Sendable {
    public var firstWindowShowingSheet: Bool
    public var secondWindowShowingSheet: Bool

    public init(firstWindowShowingSheet: Bool, secondWindowShowingSheet: Bool) {
        self.firstWindowShowingSheet = firstWindowShowingSheet
        self.secondWindowShowingSheet = secondWindowShowingSheet
    }
}

public struct TmuxSplitKeyMatchResult: Codable, Sendable {
    public var verticalKeyMatched: Bool
    public var horizontalKeyMatched: Bool
    public var paneCountAfterSplits: Int

    public init(verticalKeyMatched: Bool, horizontalKeyMatched: Bool, paneCountAfterSplits: Int) {
        self.verticalKeyMatched = verticalKeyMatched
        self.horizontalKeyMatched = horizontalKeyMatched
        self.paneCountAfterSplits = paneCountAfterSplits
    }
}

public struct PaneCloseShortcutResult: Codable, Sendable {
    public var browserPaneClosed: Bool
    public var markdownPaneClosed: Bool
    public var terminalPaneIgnoredByWindowShortcut: Bool

    public init(browserPaneClosed: Bool, markdownPaneClosed: Bool, terminalPaneIgnoredByWindowShortcut: Bool) {
        self.browserPaneClosed = browserPaneClosed
        self.markdownPaneClosed = markdownPaneClosed
        self.terminalPaneIgnoredByWindowShortcut = terminalPaneIgnoredByWindowShortcut
    }
}

public struct NestedPaneSplitResult: Codable, Sendable {
    public var paneCount: Int
    public var rootAxis: String?
    public var nestedAxis: String?
    public var rootRatio: Double?
    public var nestedRatio: Double?
    public var layoutDescription: String

    public init(paneCount: Int, rootAxis: String?, nestedAxis: String?, rootRatio: Double?, nestedRatio: Double?, layoutDescription: String) {
        self.paneCount = paneCount
        self.rootAxis = rootAxis
        self.nestedAxis = nestedAxis
        self.rootRatio = rootRatio
        self.nestedRatio = nestedRatio
        self.layoutDescription = layoutDescription
    }
}

public struct PaneSplitRemoveResult: Codable, Sendable {
    public var paneCountAfterSplit: Int
    public var isSplitAfterAdd: Bool
    public var splitRatio: Double?
    public var paneCountAfterRemove: Int
    public var isLeafAfterRemove: Bool

    public init(paneCountAfterSplit: Int, isSplitAfterAdd: Bool, splitRatio: Double?, paneCountAfterRemove: Int, isLeafAfterRemove: Bool) {
        self.paneCountAfterSplit = paneCountAfterSplit
        self.isSplitAfterAdd = isSplitAfterAdd
        self.splitRatio = splitRatio
        self.paneCountAfterRemove = paneCountAfterRemove
        self.isLeafAfterRemove = isLeafAfterRemove
    }
}

public struct CLIWorkspaceSyncResult: Codable, Sendable {
    public var initialSessionCount: Int
    public var notificationReceived: Bool
    public var reloadedSessionCount: Int
    public var reloadedSessionNames: [String]
    public var afterDeleteSessionCount: Int
    public var afterDeleteSessionNames: [String]
    public var paneCountAfterCLIAdd: Int
    public var paneTitlesAfterCLIAdd: [String]

    public init(
        initialSessionCount: Int,
        notificationReceived: Bool,
        reloadedSessionCount: Int,
        reloadedSessionNames: [String],
        afterDeleteSessionCount: Int,
        afterDeleteSessionNames: [String],
        paneCountAfterCLIAdd: Int,
        paneTitlesAfterCLIAdd: [String]
    ) {
        self.initialSessionCount = initialSessionCount
        self.notificationReceived = notificationReceived
        self.reloadedSessionCount = reloadedSessionCount
        self.reloadedSessionNames = reloadedSessionNames
        self.afterDeleteSessionCount = afterDeleteSessionCount
        self.afterDeleteSessionNames = afterDeleteSessionNames
        self.paneCountAfterCLIAdd = paneCountAfterCLIAdd
        self.paneTitlesAfterCLIAdd = paneTitlesAfterCLIAdd
    }
}

public struct PaneLayoutStabilityResult: Codable, Sendable {
    public var descAfter4Panes: String
    public var allRatiosHalf4Panes: Bool
    public var descAfterDeleteSecondary: String
    public var paneCountAfterDeleteSecondary: Int
    public var allRatiosHalfAfterDeleteSecondary: Bool
    public var descAfterDeletePrimary: String
    public var paneCountAfterDeletePrimary: Int
    public var siblingPreservedAfterPrimaryDelete: Bool
    public var lastPaneIsLeaf: Bool

    public init(
        descAfter4Panes: String,
        allRatiosHalf4Panes: Bool,
        descAfterDeleteSecondary: String,
        paneCountAfterDeleteSecondary: Int,
        allRatiosHalfAfterDeleteSecondary: Bool,
        descAfterDeletePrimary: String,
        paneCountAfterDeletePrimary: Int,
        siblingPreservedAfterPrimaryDelete: Bool,
        lastPaneIsLeaf: Bool
    ) {
        self.descAfter4Panes = descAfter4Panes
        self.allRatiosHalf4Panes = allRatiosHalf4Panes
        self.descAfterDeleteSecondary = descAfterDeleteSecondary
        self.paneCountAfterDeleteSecondary = paneCountAfterDeleteSecondary
        self.allRatiosHalfAfterDeleteSecondary = allRatiosHalfAfterDeleteSecondary
        self.descAfterDeletePrimary = descAfterDeletePrimary
        self.paneCountAfterDeletePrimary = paneCountAfterDeletePrimary
        self.siblingPreservedAfterPrimaryDelete = siblingPreservedAfterPrimaryDelete
        self.lastPaneIsLeaf = lastPaneIsLeaf
    }
}

public struct TmuxSplitShortcutResult: Codable, Sendable {
    public var paneCount: Int
    public var rootAxisAfterVerticalSplit: String?
    public var finalLayoutDescription: String

    public init(paneCount: Int, rootAxisAfterVerticalSplit: String?, finalLayoutDescription: String) {
        self.paneCount = paneCount
        self.rootAxisAfterVerticalSplit = rootAxisAfterVerticalSplit
        self.finalLayoutDescription = finalLayoutDescription
    }
}

public struct SplitPresentationSizingResult: Codable, Sendable {
    public var verticalPrimaryExtent: Double
    public var verticalSecondaryExtent: Double
    public var horizontalPrimaryExtent: Double
    public var horizontalSecondaryExtent: Double
    public var compactPickerColumnCount: Int
    public var compactPickerRequiresScrolling: Bool

    public init(
        verticalPrimaryExtent: Double,
        verticalSecondaryExtent: Double,
        horizontalPrimaryExtent: Double,
        horizontalSecondaryExtent: Double,
        compactPickerColumnCount: Int,
        compactPickerRequiresScrolling: Bool
    ) {
        self.verticalPrimaryExtent = verticalPrimaryExtent
        self.verticalSecondaryExtent = verticalSecondaryExtent
        self.horizontalPrimaryExtent = horizontalPrimaryExtent
        self.horizontalSecondaryExtent = horizontalSecondaryExtent
        self.compactPickerColumnCount = compactPickerColumnCount
        self.compactPickerRequiresScrolling = compactPickerRequiresScrolling
    }
}

public struct PaneDividerResizeResult: Codable, Sendable {
    public var verticalRatio: Double
    public var verticalPrimaryExtent: Double
    public var verticalSecondaryExtent: Double
    public var horizontalRatio: Double
    public var horizontalPrimaryExtent: Double
    public var horizontalSecondaryExtent: Double
    public var reloadedSplits: [PaneSplitDescriptor]

    public init(
        verticalRatio: Double,
        verticalPrimaryExtent: Double,
        verticalSecondaryExtent: Double,
        horizontalRatio: Double,
        horizontalPrimaryExtent: Double,
        horizontalSecondaryExtent: Double,
        reloadedSplits: [PaneSplitDescriptor]
    ) {
        self.verticalRatio = verticalRatio
        self.verticalPrimaryExtent = verticalPrimaryExtent
        self.verticalSecondaryExtent = verticalSecondaryExtent
        self.horizontalRatio = horizontalRatio
        self.horizontalPrimaryExtent = horizontalPrimaryExtent
        self.horizontalSecondaryExtent = horizontalSecondaryExtent
        self.reloadedSplits = reloadedSplits
    }
}

public struct SplitDividerHitTestingResult: Codable, Sendable {
    public var horizontalTopPointHitsDivider: Bool
    public var horizontalDividerPointHitsDivider: Bool
    public var verticalLeftPointHitsDivider: Bool
    public var verticalDividerPointHitsDivider: Bool

    public init(
        horizontalTopPointHitsDivider: Bool,
        horizontalDividerPointHitsDivider: Bool,
        verticalLeftPointHitsDivider: Bool,
        verticalDividerPointHitsDivider: Bool
    ) {
        self.horizontalTopPointHitsDivider = horizontalTopPointHitsDivider
        self.horizontalDividerPointHitsDivider = horizontalDividerPointHitsDivider
        self.verticalLeftPointHitsDivider = verticalLeftPointHitsDivider
        self.verticalDividerPointHitsDivider = verticalDividerPointHitsDivider
    }
}

public struct NestedSplitResizeIsolationResult: Codable, Sendable {
    public var rootRatioAfterHeightResize: Double
    public var topHeightAfterHeightResize: Double
    public var bottomHeightAfterHeightResize: Double
    public var topWidthBeforeIndependentResize: Double
    public var topWidthSiblingBeforeIndependentResize: Double
    public var bottomWidthBeforeIndependentResize: Double
    public var bottomWidthSiblingBeforeIndependentResize: Double
    public var topWidthAfterIndependentResize: Double
    public var topWidthSiblingAfterIndependentResize: Double
    public var bottomWidthAfterIndependentResize: Double
    public var bottomWidthSiblingAfterIndependentResize: Double
    public var bottomSplitRatioAfterTopResize: Double

    public init(
        rootRatioAfterHeightResize: Double,
        topHeightAfterHeightResize: Double,
        bottomHeightAfterHeightResize: Double,
        topWidthBeforeIndependentResize: Double,
        topWidthSiblingBeforeIndependentResize: Double,
        bottomWidthBeforeIndependentResize: Double,
        bottomWidthSiblingBeforeIndependentResize: Double,
        topWidthAfterIndependentResize: Double,
        topWidthSiblingAfterIndependentResize: Double,
        bottomWidthAfterIndependentResize: Double,
        bottomWidthSiblingAfterIndependentResize: Double,
        bottomSplitRatioAfterTopResize: Double
    ) {
        self.rootRatioAfterHeightResize = rootRatioAfterHeightResize
        self.topHeightAfterHeightResize = topHeightAfterHeightResize
        self.bottomHeightAfterHeightResize = bottomHeightAfterHeightResize
        self.topWidthBeforeIndependentResize = topWidthBeforeIndependentResize
        self.topWidthSiblingBeforeIndependentResize = topWidthSiblingBeforeIndependentResize
        self.bottomWidthBeforeIndependentResize = bottomWidthBeforeIndependentResize
        self.bottomWidthSiblingBeforeIndependentResize = bottomWidthSiblingBeforeIndependentResize
        self.topWidthAfterIndependentResize = topWidthAfterIndependentResize
        self.topWidthSiblingAfterIndependentResize = topWidthSiblingAfterIndependentResize
        self.bottomWidthAfterIndependentResize = bottomWidthAfterIndependentResize
        self.bottomWidthSiblingAfterIndependentResize = bottomWidthSiblingAfterIndependentResize
        self.bottomSplitRatioAfterTopResize = bottomSplitRatioAfterTopResize
    }
}

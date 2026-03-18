import AppKit
import ApplicationServices
import Foundation

public struct TerminalUITestResult: Codable, Sendable {
    public var frontmostApplication: String
    public var editorValue: String
    public var editorFocused: Bool

    public init(frontmostApplication: String, editorValue: String, editorFocused: Bool) {
        self.frontmostApplication = frontmostApplication
        self.editorValue = editorValue
        self.editorFocused = editorFocused
    }
}

public struct TerminalUILayoutResult: Codable, Sendable {
    public var widthRatio: Double
    public var heightRatio: Double

    public init(widthRatio: Double, heightRatio: Double) {
        self.widthRatio = widthRatio
        self.heightRatio = heightRatio
    }
}

public struct PaneChromeTestResult: Codable, Sendable {
    public var paneCount: Int
    public var titleVisible: Bool
    public var closeButtonVisible: Bool

    public init(paneCount: Int, titleVisible: Bool, closeButtonVisible: Bool) {
        self.paneCount = paneCount
        self.titleVisible = titleVisible
        self.closeButtonVisible = closeButtonVisible
    }
}

public struct TerminalPaneLifecycleResult: Codable, Sendable {
    public var paneCount: Int
    public var paneClosed: Bool

    public init(paneCount: Int, paneClosed: Bool) {
        self.paneCount = paneCount
        self.paneClosed = paneClosed
    }
}

public struct FilePickerTestResult: Codable, Sendable {
    public var selectedPath: String

    public init(selectedPath: String) {
        self.selectedPath = selectedPath
    }
}

public struct PaneDividerDragAutomationResult: Codable, Sendable {
    public var initialRatio: Double
    public var finalRatio: Double
    public var debugLog: String

    public init(initialRatio: Double, finalRatio: Double, debugLog: String) {
        self.initialRatio = initialRatio
        self.finalRatio = finalRatio
        self.debugLog = debugLog
    }
}

public struct AccessibilityNodeSnapshot: Codable, Sendable {
    public var identifier: String?
    public var role: String?
    public var frame: String?

    public init(identifier: String?, role: String?, frame: String?) {
        self.identifier = identifier
        self.role = role
        self.frame = frame
    }
}

public enum TerminalUITestError: Error, LocalizedError {
    case accessibilityUnavailable
    case appLaunchFailed
    case appWindowNotFound
    case surfaceNotFound
    case editorFrameUnavailable
    case transcriptExpectationFailed(String)
    case automationResponseMissing

    public var errorDescription: String? {
        switch self {
        case .accessibilityUnavailable:
            return "Accessibility automation is not available"
        case .appLaunchFailed:
            return "Failed to launch MyIDESampleMacApp"
        case .appWindowNotFound:
            return "Unable to find the app window"
        case .surfaceNotFound:
            return "Unable to find the terminal surface"
        case .editorFrameUnavailable:
            return "Unable to determine the terminal editor frame"
        case .transcriptExpectationFailed(let expected):
            return "Terminal transcript never contained expected text: \(expected)"
        case .automationResponseMissing:
            return "Unable to read terminal automation response"
        }
    }
}

@MainActor
public enum TerminalUIAutomation {
    public static func runTerminalClickTypingTest(appExecutableURL: URL, typedText: String) throws -> TerminalUITestResult {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("myide-divider-debug-\(UUID().uuidString).log")
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
            try? FileManager.default.removeItem(at: debugLogURL)
        }

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(with: workspaceURL, automationDirectory: automationDirectory)

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let finder = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Finder" })
        finder?.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.3)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        guard let surfaceElement = waitForTerminalSurface(in: windowElement) else {
            throw TerminalUITestError.surfaceNotFound
        }

        let frame = try frame(of: surfaceElement)
        click(at: CGPoint(x: frame.midX, y: frame.midY))
        waitFor(seconds: 0.3)

        sendText(typedText)
        let value = try waitForTerminalSnapshot(containing: typedText, in: automationDirectory)

        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let focused = frontmost == "MyIDESampleMacApp"

        return TerminalUITestResult(
            frontmostApplication: frontmost,
            editorValue: value,
            editorFocused: focused
        )
    }

    public static func runTerminalCommandTest(
        appExecutableURL: URL,
        command: String,
        expectedOutput: String
    ) throws -> TerminalUITestResult {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("myide-divider-debug-\(UUID().uuidString).log")
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
            try? FileManager.default.removeItem(at: debugLogURL)
        }

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(
            with: workspaceURL,
            automationDirectory: automationDirectory,
            extra: ["MYIDE_DIVIDER_DEBUG_LOG": debugLogURL.path]
        )

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let finder = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Finder" })
        finder?.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.3)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        guard let surfaceElement = waitForTerminalSurface(in: windowElement) else {
            throw TerminalUITestError.surfaceNotFound
        }

        let frame = try frame(of: surfaceElement)
        click(at: CGPoint(x: frame.midX, y: frame.midY))
        waitFor(seconds: 0.3)

        sendText(command)
        sendKeyCode(36)

        let value = try waitForTerminalSnapshot(containing: expectedOutput, in: automationDirectory)
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let focused = frontmost == "MyIDESampleMacApp"

        return TerminalUITestResult(
            frontmostApplication: frontmost,
            editorValue: value,
            editorFocused: focused
        )
    }

    public static func runTerminalLayoutTest(appExecutableURL: URL) throws -> TerminalUILayoutResult {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("myide-divider-debug-\(UUID().uuidString).log")
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
            try? FileManager.default.removeItem(at: debugLogURL)
        }

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(
            with: workspaceURL,
            automationDirectory: automationDirectory,
            extra: ["MYIDE_DIVIDER_DEBUG_LOG": debugLogURL.path]
        )
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let finder = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Finder" })
        finder?.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.3)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        guard let surfaceElement = waitForTerminalSurface(in: windowElement) else {
            throw TerminalUITestError.surfaceNotFound
        }

        guard let terminalElement = waitForElement(identifier: "embedded-terminal-", in: windowElement, partialMatch: true) else {
            throw TerminalUITestError.surfaceNotFound
        }

        let editorFrame = try frame(of: terminalElement)
        let surfaceFrame = try frame(of: surfaceElement)

        return TerminalUILayoutResult(
            widthRatio: editorFrame.width / surfaceFrame.width,
            heightRatio: editorFrame.height / surfaceFrame.height
        )
    }

    public static func runPaneChromeTest(appExecutableURL: URL, expectedPaneTitle: String) throws -> PaneChromeTestResult {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("myide-divider-debug-\(UUID().uuidString).log")
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
            try? FileManager.default.removeItem(at: debugLogURL)
        }

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(
            with: workspaceURL,
            automationDirectory: automationDirectory,
            extra: ["MYIDE_DIVIDER_DEBUG_LOG": debugLogURL.path]
        )
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        guard let paneContainer = waitForElement(identifier: "pane-container-terminal", in: windowElement) else {
            throw TerminalUITestError.surfaceNotFound
        }

        return PaneChromeTestResult(
            paneCount: countElements(identifierPrefix: "pane-container-", in: windowElement),
            titleVisible: containsText(expectedPaneTitle, in: paneContainer),
            closeButtonVisible: containsRole(kAXButtonRole as String, in: paneContainer)
        )
    }

    public static func runTerminalEndOfTransmissionTest(appExecutableURL: URL) throws -> TerminalPaneLifecycleResult {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("myide-divider-debug-\(UUID().uuidString).log")
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
            try? FileManager.default.removeItem(at: debugLogURL)
        }

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(
            with: workspaceURL,
            automationDirectory: automationDirectory,
            extra: ["MYIDE_DIVIDER_DEBUG_LOG": debugLogURL.path]
        )
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        guard let surfaceElement = waitForTerminalSurface(in: windowElement) else {
            throw TerminalUITestError.surfaceNotFound
        }

        let frame = try frame(of: surfaceElement)
        click(at: CGPoint(x: frame.midX, y: frame.midY))
        waitFor(seconds: 0.3)

        _ = try? requestTerminalSnapshot(in: automationDirectory)
        sendShortcut(keyCode: 2, flags: .maskControl)

        let paneCount = waitUntil(timeout: 10, pollInterval: 0.2) {
            let count = countElements(identifierPrefix: "pane-container-", in: windowElement)
            return count == 0 ? count : nil
        } ?? countElements(identifierPrefix: "pane-container-", in: windowElement)

        return TerminalPaneLifecycleResult(
            paneCount: paneCount,
            paneClosed: paneCount == 0
        )
    }

    public static func runPreviewFilePickerTest(appExecutableURL: URL, selectedFilePath: String) throws -> FilePickerTestResult {
        let pane = WorkspacePane.markdownPreview(title: "Preview", filePath: "")
        let workspace = workspaceForSinglePane(pane)
        return try runFilePickerTest(
            appExecutableURL: appExecutableURL,
            workspace: workspace,
            selectedFilePath: selectedFilePath,
            buttonIdentifier: "preview-file-browse-\(pane.id)",
            fieldIdentifier: "preview-file-path-\(pane.id)"
        )
    }

    public static func runDiffFilePickerTest(appExecutableURL: URL, selectedFilePath: String) throws -> FilePickerTestResult {
        let pane = WorkspacePane.diff(title: "Diff", leftPath: "", rightPath: "")
        let workspace = workspaceForSinglePane(pane)
        return try runFilePickerTest(
            appExecutableURL: appExecutableURL,
            workspace: workspace,
            selectedFilePath: selectedFilePath,
            buttonIdentifier: "diff-left-browse-\(pane.id)",
            fieldIdentifier: "diff-left-path-\(pane.id)"
        )
    }

    public static func debugTerminalAncestry(appExecutableURL: URL) throws -> [AccessibilityNodeSnapshot] {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
        }

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(with: workspaceURL, automationDirectory: automationDirectory)
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        guard let surfaceElement = waitForTerminalSurface(in: windowElement) else {
            throw TerminalUITestError.surfaceNotFound
        }

        return ancestry(of: surfaceElement)
    }

    public static func runPaneDividerDragTest(appExecutableURL: URL) throws -> PaneDividerDragAutomationResult {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("myide-divider-debug-\(UUID().uuidString).log")
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
            try? FileManager.default.removeItem(at: debugLogURL)
        }

        let fixture = workspaceForRootVerticalSplit()
        try WorkspaceStore.save(fixture.workspace, to: workspaceURL)

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(
            with: workspaceURL,
            automationDirectory: automationDirectory,
            extra: ["MYIDE_DIVIDER_DEBUG_LOG": debugLogURL.path]
        )
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 1)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        guard let dividerElement = waitForElement(identifier: "pane-divider-root", in: windowElement) else {
            throw TerminalUITestError.surfaceNotFound
        }

        let dividerFrame = try frame(of: dividerElement)
        let startPoint = CGPoint(x: dividerFrame.midX, y: dividerFrame.midY)
        let endPoint = CGPoint(x: startPoint.x - 120, y: startPoint.y)
        drag(from: startPoint, to: endPoint)

        let finalRatio = try waitForUpdatedRootRatio(
            workspaceURL: workspaceURL,
            sessionID: fixture.sessionID,
            windowID: fixture.windowID
        )

        let debugLog = (try? String(contentsOf: debugLogURL, encoding: .utf8)) ?? ""
        return PaneDividerDragAutomationResult(initialRatio: 0.5, finalRatio: finalRatio, debugLog: debugLog)
    }

    private static func terminateExistingAppInstances() {
        NSWorkspace.shared.runningApplications
            .filter { $0.localizedName == "MyIDESampleMacApp" }
            .forEach { app in
                app.forceTerminate()
            }
    }

    private static func waitForRunningApplication(pid: pid_t) -> NSRunningApplication? {
        waitUntil(timeout: 10) {
            NSRunningApplication(processIdentifier: pid)
        }
    }

    private static func temporaryWorkspaceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("myide-ui-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    private static func temporaryAutomationDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("myide-automation-\(UUID().uuidString)", isDirectory: true)
    }

    private static func cleanupTemporaryWorkspace(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static func cleanupTemporaryDirectory(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func mergedEnvironment(with workspaceURL: URL, automationDirectory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["MYIDE_WORKSPACE_PATH"] = workspaceURL.path
        environment["MYIDE_AUTOMATION_DIR"] = automationDirectory.path
        return environment
    }

    private static func mergedEnvironment(
        with workspaceURL: URL,
        automationDirectory: URL,
        extra: [String: String]
    ) -> [String: String] {
        var environment = mergedEnvironment(with: workspaceURL, automationDirectory: automationDirectory)
        for (key, value) in extra {
            environment[key] = value
        }
        return environment
    }

    private static func waitForWindow(in appElement: AXUIElement) -> AXUIElement? {
        waitUntil(timeout: 10) {
            guard let windows = copyAttribute(appElement, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
                return nil
            }

            return windows.first
        }
    }

    private static func waitForTerminalSurface(in root: AXUIElement) -> AXUIElement? {
        if let taggedSurface = waitForElement(identifier: "terminal-pane-surface", in: root) {
            return taggedSurface
        }

        return waitForElement(identifier: "embedded-terminal-", in: root, partialMatch: true)
    }

    private static func waitForElement(identifier: String, in root: AXUIElement, partialMatch: Bool = false) -> AXUIElement? {
        waitUntil(timeout: 10) {
            findElement(in: root) { element in
                guard let rawIdentifier = copyAttribute(element, attribute: kAXIdentifierAttribute) else {
                    return false
                }

                guard let candidate = rawIdentifier as? String else {
                    return false
                }

                return partialMatch ? candidate.contains(identifier) : candidate == identifier
            }
        }
    }

    private static func waitForElement(withTitle title: String, in root: AXUIElement) -> AXUIElement? {
        waitUntil(timeout: 10) {
            findElement(in: root) { element in
                let value = stringValue(of: element)
                return value == title
            }
        }
    }

    private static func ancestry(of element: AXUIElement) -> [AccessibilityNodeSnapshot] {
        var snapshots: [AccessibilityNodeSnapshot] = []
        var current: AXUIElement? = element

        while let node = current {
            let identifier = copyAttribute(node, attribute: kAXIdentifierAttribute) as? String
            let role = copyAttribute(node, attribute: kAXRoleAttribute) as? String
            let frameString: String?
            if let frame = try? frame(of: node) {
                frameString = NSStringFromRect(frame)
            } else {
                frameString = nil
            }

            snapshots.append(
                AccessibilityNodeSnapshot(
                    identifier: identifier,
                    role: role,
                    frame: frameString
                )
            )

            if let parent = copyAttribute(node, attribute: kAXParentAttribute) {
                current = unsafeDowncast(parent, to: AXUIElement.self)
            } else {
                current = nil
            }
        }

        return snapshots
    }

    private static func findElement(in root: AXUIElement, matcher: (AXUIElement) -> Bool) -> AXUIElement? {
        if matcher(root) {
            return root
        }

        guard let children = copyAttribute(root, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let found = findElement(in: child, matcher: matcher) {
                return found
            }
        }

        return nil
    }

    private static func countElements(identifierPrefix: String, in root: AXUIElement) -> Int {
        identifiers(matchingPrefix: identifierPrefix, in: root).count
    }

    private static func countElements(in root: AXUIElement, matcher: (AXUIElement) -> Bool) -> Int {
        var total = matcher(root) ? 1 : 0
        guard let children = copyAttribute(root, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return total
        }

        for child in children {
            total += countElements(in: child, matcher: matcher)
        }

        return total
    }

    private static func identifiers(matchingPrefix prefix: String, in root: AXUIElement) -> Set<String> {
        var matches: Set<String> = []
        if let identifier = copyAttribute(root, attribute: kAXIdentifierAttribute) as? String, identifier.hasPrefix(prefix) {
            matches.insert(identifier)
        }

        guard let children = copyAttribute(root, attribute: kAXChildrenAttribute) as? [AXUIElement] else {
            return matches
        }

        for child in children {
            matches.formUnion(identifiers(matchingPrefix: prefix, in: child))
        }

        return matches
    }

    private static func containsText(_ text: String, in root: AXUIElement) -> Bool {
        findElement(in: root) { element in
            let title = copyAttribute(element, attribute: kAXTitleAttribute) as? String
            let value = copyAttribute(element, attribute: kAXValueAttribute) as? String
            let description = copyAttribute(element, attribute: kAXDescriptionAttribute) as? String
            return title == text || value == text || description == text
        } != nil
    }

    private static func containsRole(_ role: String, in root: AXUIElement) -> Bool {
        findElement(in: root) { element in
            (copyAttribute(element, attribute: kAXRoleAttribute) as? String) == role
        } != nil
    }

    private static func frame(of element: AXUIElement) throws -> CGRect {
        guard
            let positionValue = copyAttribute(element, attribute: kAXPositionAttribute),
            let sizeValue = copyAttribute(element, attribute: kAXSizeAttribute)
        else {
            throw TerminalUITestError.editorFrameUnavailable
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    private static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func drag(from start: CGPoint, to end: CGPoint, steps: Int = 12) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        waitFor(seconds: 0.05)

        for step in 1...max(steps, 1) {
            let progress = CGFloat(step) / CGFloat(max(steps, 1))
            let point = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            event?.post(tap: .cghidEventTap)
            waitFor(seconds: 0.02)
        }

        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        up?.post(tap: .cghidEventTap)
        waitFor(seconds: 0.1)
    }

    private static func sendShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func sendKeyCode(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func sendText(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        for scalar in text.utf16 {
            var value = scalar
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }

        waitFor(seconds: 0.2)
    }

    private static func waitForTerminalSnapshot(containing expected: String, in automationDirectory: URL) throws -> String {
        if let value = waitUntil(timeout: 12, pollInterval: 0.3, body: { () -> String? in
            guard let snapshot = try? requestTerminalSnapshot(in: automationDirectory) else {
                return nil
            }

            return snapshot.contains(expected) ? snapshot : nil
        }) {
            return value
        }

        let latestValue = (try? requestTerminalSnapshot(in: automationDirectory)) ?? ""
        if latestValue.contains(expected) {
            return latestValue
        }

        throw TerminalUITestError.transcriptExpectationFailed(expected)
    }

    private static func requestTerminalSnapshot(in automationDirectory: URL) throws -> String {
        try FileManager.default.createDirectory(at: automationDirectory, withIntermediateDirectories: true)
        let requestID = UUID().uuidString
        let responseURL = automationDirectory.appendingPathComponent("\(requestID).json")

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("myide.terminal-automation.request"),
            object: nil,
            userInfo: [
                "requestID": requestID,
                "action": TerminalAutomationAction.snapshot.rawValue
            ],
            options: [.deliverImmediately]
        )

        guard let responseData = waitUntil(timeout: 3, pollInterval: 0.1, body: { () -> Data? in
            try? Data(contentsOf: responseURL)
        }) else {
            throw TerminalUITestError.automationResponseMissing
        }

        let response = try JSONDecoder().decode(TerminalAutomationSnapshotResponse.self, from: responseData)
        return response.snapshot
    }

    private static func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        if let value = copyAttribute(element, attribute: kAXValueAttribute) as? String {
            return value
        }

        if let title = copyAttribute(element, attribute: kAXTitleAttribute) as? String {
            return title
        }

        return nil
    }

    private static func workspaceForSinglePane(_ pane: WorkspacePane) -> Workspace {
        let window = WorkspaceWindow(title: "Main", panes: [pane])
        let session = WorkspaceSession(name: "Main Session", windows: [window])
        return Workspace(sessions: [session])
    }

    private static func workspaceForRootVerticalSplit() -> (workspace: Workspace, sessionID: String, windowID: String) {
        let cwd = FileManager.default.currentDirectoryPath
        let leftPane = WorkspacePane.terminal(title: "Left", provider: .terminal, workingDirectory: cwd)
        let rightPane = WorkspacePane.terminal(title: "Right", provider: .terminal, workingDirectory: cwd)
        let window = WorkspaceWindow(
            title: "Main",
            panes: [leftPane, rightPane],
            layout: .split(axis: .vertical, ratio: 0.5, primary: .leaf(leftPane.id), secondary: .leaf(rightPane.id))
        )
        let session = WorkspaceSession(name: "Main Session", windows: [window])
        let workspace = Workspace(sessions: [session])
        return (workspace, session.id, window.id)
    }

    private static func waitForUpdatedRootRatio(
        workspaceURL: URL,
        sessionID: String,
        windowID: String
    ) throws -> Double {
        if let updatedRatio = waitUntil(timeout: 5, pollInterval: 0.2, body: { () -> Double? in
            guard
                let workspace = try? WorkspaceStore.load(from: workspaceURL),
                let descriptor = try? workspace.splitDescriptor(
                    sessionID: sessionID,
                    windowID: windowID,
                    splitPath: .root
                ),
                descriptor.ratio < 0.49
            else {
                return nil
            }

            return descriptor.ratio
        }) {
            return updatedRatio
        }

        let workspace = try WorkspaceStore.load(from: workspaceURL)
        let descriptor = try workspace.splitDescriptor(sessionID: sessionID, windowID: windowID, splitPath: .root)
        return descriptor.ratio
    }

    private static func runFilePickerTest(
        appExecutableURL: URL,
        workspace: Workspace,
        selectedFilePath: String,
        buttonIdentifier: String,
        fieldIdentifier: String
    ) throws -> FilePickerTestResult {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        try WorkspaceStore.save(workspace, to: workspaceURL)
        defer {
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
        }

        let process = Process()
        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(
            with: workspaceURL,
            automationDirectory: automationDirectory,
            extra: ["MYIDE_AUTOMATION_SELECTED_FILE": selectedFilePath]
        )
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        let buttonElement = waitForElement(identifier: buttonIdentifier, in: windowElement)
            ?? waitForElement(withTitle: "Browse…", in: windowElement)
        guard let buttonElement else {
            throw TerminalUITestError.surfaceNotFound
        }

        let buttonFrame = try frame(of: buttonElement)
        click(at: CGPoint(x: buttonFrame.midX, y: buttonFrame.midY))

        guard let fieldValue = waitUntil(timeout: 5, pollInterval: 0.1, body: { () -> String? in
            selectedFilePathFromWorkspace(in: workspaceURL, preferredFieldIdentifier: fieldIdentifier)
        }) else {
            throw TerminalUITestError.transcriptExpectationFailed(selectedFilePath)
        }

        return FilePickerTestResult(selectedPath: fieldValue)
    }

    private static func selectedFilePathFromWorkspace(in workspaceURL: URL, preferredFieldIdentifier: String) -> String? {
        guard let workspace = try? WorkspaceStore.load(from: workspaceURL),
              let pane = workspace.sessions.first?.windows.first?.panes.first else {
            return nil
        }

        if preferredFieldIdentifier.contains("preview") {
            return pane.preview?.filePath
        }

        if preferredFieldIdentifier.contains("diff-left") {
            return pane.diff?.leftPath
        }

        if preferredFieldIdentifier.contains("diff-right") {
            return pane.diff?.rightPath
        }

        return nil
    }

    private static func waitUntil<T>(timeout: TimeInterval, pollInterval: TimeInterval = 0.1, body: () -> T?) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = body() {
                return value
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }

        return nil
    }

    private static func waitFor(seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

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
        let process = Process()
        var launchedApp: NSRunningApplication?
        defer {
            cleanupLaunchedApp(process, app: launchedApp)
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
        }

        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(with: workspaceURL, automationDirectory: automationDirectory)

        try process.run()

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }
        launchedApp = app

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let finder = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Finder" })
        finder?.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.3)

        app.activate(options: [.activateAllWindows])
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

        _ = waitUntil(timeout: 5, pollInterval: 0.2, body: { () -> String? in
            try? requestTerminalSnapshot(in: automationDirectory)
        })
        sendText(typedText)
        let value = try waitForTerminalSnapshot(containing: typedText, in: automationDirectory)

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.2)
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
        let process = Process()
        var launchedApp: NSRunningApplication?
        defer {
            cleanupLaunchedApp(process, app: launchedApp)
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
        }

        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(
            with: workspaceURL,
            automationDirectory: automationDirectory,
            startupCommand: command
        )

        try process.run()

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }
        launchedApp = app

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let finder = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Finder" })
        finder?.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.3)

        app.activate(options: [.activateAllWindows])
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

        let value = try waitForTerminalSnapshot(containing: expectedOutput, in: automationDirectory)
        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.2)
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
        let process = Process()
        var launchedApp: NSRunningApplication?
        defer {
            cleanupLaunchedApp(process, app: launchedApp)
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
        }

        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(with: workspaceURL, automationDirectory: automationDirectory)
        try process.run()

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }
        launchedApp = app

        app.activate(options: [.activateAllWindows])
        waitFor(seconds: 0.5)

        let appElement = AXUIElementCreateApplication(process.processIdentifier)
        guard let windowElement = waitForWindow(in: appElement) else {
            throw TerminalUITestError.appWindowNotFound
        }

        let windowFrame = try frame(of: windowElement)
        click(at: CGPoint(x: windowFrame.midX, y: windowFrame.midY))
        waitFor(seconds: 0.3)

        _ = waitUntil(timeout: 5, pollInterval: 0.2, body: { () -> String? in
            try? requestTerminalSnapshot(in: automationDirectory)
        })
        let layout = try requestTerminalLayout(in: automationDirectory)

        return TerminalUILayoutResult(
            widthRatio: layout.widthRatio,
            heightRatio: layout.heightRatio
        )
    }

    public static func debugTerminalAncestry(appExecutableURL: URL) throws -> [AccessibilityNodeSnapshot] {
        guard AXIsProcessTrusted() else {
            throw TerminalUITestError.accessibilityUnavailable
        }

        terminateExistingAppInstances()
        let workspaceURL = temporaryWorkspaceURL()
        let automationDirectory = temporaryAutomationDirectory()
        let process = Process()
        var launchedApp: NSRunningApplication?
        defer {
            cleanupLaunchedApp(process, app: launchedApp)
            cleanupTemporaryWorkspace(at: workspaceURL)
            cleanupTemporaryDirectory(at: automationDirectory)
        }

        process.executableURL = appExecutableURL
        process.environment = mergedEnvironment(with: workspaceURL, automationDirectory: automationDirectory)
        try process.run()

        guard let app = waitForRunningApplication(pid: process.processIdentifier) else {
            throw TerminalUITestError.appLaunchFailed
        }
        launchedApp = app

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

        return ancestry(of: surfaceElement)
    }

    private static func terminateExistingAppInstances() {
        NSWorkspace.shared.runningApplications
            .filter { $0.localizedName == "MyIDESampleMacApp" }
            .forEach { app in
                app.forceTerminate()
            }
    }

    private static func cleanupLaunchedApp(_ process: Process, app: NSRunningApplication?) {
        app?.forceTerminate()
        _ = waitUntil(timeout: 3, pollInterval: 0.1) {
            process.isRunning ? nil : true
        }

        if process.isRunning {
            process.terminate()
            _ = waitUntil(timeout: 2, pollInterval: 0.1) {
                process.isRunning ? nil : true
            }
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

    private static func mergedEnvironment(
        with workspaceURL: URL,
        automationDirectory: URL,
        startupCommand: String? = nil
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["MYIDE_WORKSPACE_PATH"] = workspaceURL.path
        environment["MYIDE_AUTOMATION_DIR"] = automationDirectory.path
        if let startupCommand, !startupCommand.isEmpty {
            environment["MYIDE_AUTOMATION_START_COMMAND"] = startupCommand
        }
        return environment
    }

    private static func waitForWindow(in appElement: AXUIElement) -> AXUIElement? {
        waitUntil(timeout: 10) {
            if let focusedWindow = copyAttribute(appElement, attribute: kAXFocusedWindowAttribute) {
                return unsafeDowncast(focusedWindow, to: AXUIElement.self)
            }

            guard let windows = copyAttribute(appElement, attribute: kAXWindowsAttribute) as? [AXUIElement] else {
                return nil
            }

            return windows.first
        }
    }

    private static func waitForTerminalSurface(in root: AXUIElement) -> AXUIElement? {
        waitForElement(identifier: "terminal-pane-surface", in: root)
            ?? waitForElement(identifier: "pane-container-terminal", in: root)
            ?? waitForElement(identifier: "embedded-terminal-", in: root, partialMatch: true)
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "on run argv",
            "-e",
            "tell application \"System Events\" to keystroke (item 1 of argv)",
            "-e",
            "end run",
            text
        ]
        try? process.run()
        process.waitUntilExit()
        waitFor(seconds: 0.25)
    }

    private static func pasteTextViaAppleScript(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to keystroke \"v\" using command down"
        ]
        try? process.run()
        process.waitUntilExit()
        waitFor(seconds: 0.3)

        pasteboard.clearContents()
        if let previousString, !previousString.isEmpty {
            pasteboard.setString(previousString, forType: .string)
        }
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

    private static func requestTerminalLayout(in automationDirectory: URL) throws -> TerminalAutomationLayoutResponse {
        try FileManager.default.createDirectory(at: automationDirectory, withIntermediateDirectories: true)
        let requestID = UUID().uuidString
        let responseURL = automationDirectory.appendingPathComponent("\(requestID).json")

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("myide.terminal-automation.request"),
            object: nil,
            userInfo: [
                "requestID": requestID,
                "action": TerminalAutomationAction.layout.rawValue
            ],
            options: [.deliverImmediately]
        )

        guard let responseData = waitUntil(timeout: 3, pollInterval: 0.1, body: { () -> Data? in
            try? Data(contentsOf: responseURL)
        }) else {
            throw TerminalUITestError.automationResponseMissing
        }

        return try JSONDecoder().decode(TerminalAutomationLayoutResponse.self, from: responseData)
    }


    private static func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
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

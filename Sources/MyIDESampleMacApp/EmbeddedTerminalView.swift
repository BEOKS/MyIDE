import AppKit
import SwiftTerm
import MyIDECore

private final class EmbeddedTerminalProcessDelegate: LocalProcessTerminalViewDelegate {
    private let onProcessTerminated: (Int32?) -> Void

    init(onProcessTerminated: @escaping (Int32?) -> Void) {
        self.onProcessTerminated = onProcessTerminated
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        _ = source
        _ = newCols
        _ = newRows
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        _ = source
        _ = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        _ = source
        _ = directory
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        _ = source
        onProcessTerminated(exitCode)
    }
}

final class EmbeddedTerminalView: LocalProcessTerminalView {
    let paneID: String
    private let configuration: TerminalPaneConfiguration
    private let onProcessTerminated: () -> Void
    private let lifecycleController = TerminalPaneLifecycleController()
    private lazy var terminalProcessDelegate = EmbeddedTerminalProcessDelegate { [weak self] exitCode in
        self?.handleProcessTermination(exitCode: exitCode)
    }
    private var hasStartedProcess = false
    private var hasHandledProcessTermination = false

    init(paneID: String, configuration: TerminalPaneConfiguration, onProcessTerminated: @escaping () -> Void) {
        self.paneID = paneID
        self.configuration = configuration
        self.onProcessTerminated = onProcessTerminated
        super.init(frame: .zero)
        setupAppearance()
        processDelegate = terminalProcessDelegate
        setAccessibilityElement(true)
        setAccessibilityIdentifier("embedded-terminal-\(paneID)")
        setAccessibilityLabel("Embedded Terminal \(paneID)")
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(focusWindowForInteraction))
        addGestureRecognizer(clickGesture)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            prepareForTearDown()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func removeFromSuperview() {
        prepareForTearDown()
        super.removeFromSuperview()
    }

    deinit {
        prepareForTearDown()
        terminate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }

        TerminalAutomationBridge.shared.registerTerminal(self)
        startIfNeeded()
    }

    @objc
    private func focusWindowForInteraction() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    func terminalSnapshot() -> String {
        String(decoding: getTerminal().getBufferAsData(), as: UTF8.self)
    }

    private func prepareForTearDown() {
        lifecycleController.beginTearDown()
        unregisterTerminal()
    }

    private func unregisterTerminal() {
        let terminalPaneID = paneID
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                TerminalAutomationBridge.shared.unregisterTerminal(paneID: terminalPaneID)
            }
            return
        }

        DispatchQueue.main.async {
            TerminalAutomationBridge.shared.unregisterTerminal(paneID: terminalPaneID)
        }
    }

    private func handleProcessTermination(exitCode: Int32?) {
        _ = exitCode
        guard lifecycleController.shouldPropagateProcessTermination() else {
            return
        }

        guard !hasHandledProcessTermination else {
            return
        }

        hasHandledProcessTermination = true
        Task { @MainActor [onProcessTerminated] in
            onProcessTerminated()
        }
    }

    private func setupAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.cgColor

        do {
            try setUseMetal(false)
        } catch {
        }

        let background = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 1)
        let foreground = NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.95, alpha: 1)
        nativeBackgroundColor = background
        nativeForegroundColor = foreground
        caretColor = NSColor(calibratedRed: 0.5, green: 0.96, blue: 0.65, alpha: 1)
        optionAsMetaKey = true
        font = NSFont(name: "SF Mono", size: 14) ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        getTerminal().setCursorStyle(.steadyBlock)
    }

    private func startIfNeeded() {
        guard !hasStartedProcess else {
            return
        }

        hasStartedProcess = true
        let launchPlan = TerminalProviderRuntime.launchPlan(
            for: configuration.provider,
            shellPath: currentUserShell()
        )
        startProcess(
            executable: launchPlan.shellPath,
            environment: launchPlan.environment,
            execName: launchPlan.execName,
            currentDirectory: configuration.workingDirectory
        )
    }

    private func currentUserShell() -> String {
        let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)
        guard bufsize > 0 else {
            return "/bin/zsh"
        }

        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
        defer { buffer.deallocate() }

        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>? = nil
        guard getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) == 0, result != nil else {
            return "/bin/zsh"
        }

        return String(cString: pwd.pw_shell)
    }
}

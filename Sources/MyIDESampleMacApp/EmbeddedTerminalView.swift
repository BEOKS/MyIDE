import AppKit
import SwiftTerm
import MyIDECore

final class EmbeddedTerminalView: LocalProcessTerminalView, LocalProcessTerminalViewDelegate {
    let paneID: String
    private let configuration: TerminalPaneConfiguration
    private var hasStartedProcess = false

    init(paneID: String, configuration: TerminalPaneConfiguration) {
        self.paneID = paneID
        self.configuration = configuration
        super.init(frame: .zero)
        setupAppearance()
        processDelegate = self
        setAccessibilityElement(true)
        setAccessibilityIdentifier("embedded-terminal-\(paneID)")
        setAccessibilityLabel("Embedded Terminal \(paneID)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        terminate()
        Task { @MainActor in
            TerminalAutomationBridge.shared.unregisterTerminal(paneID: self.paneID)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }

        TerminalAutomationBridge.shared.registerTerminal(self)
        startIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    func terminalSnapshot() -> String {
        String(decoding: getTerminal().getBufferAsData(), as: UTF8.self)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        _ = newCols
        _ = newRows
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        _ = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        _ = source
        _ = directory
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        _ = source
        _ = exitCode
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
        let shell = currentUserShell()
        let shellIdiom = "-" + URL(fileURLWithPath: shell).lastPathComponent
        startProcess(
            executable: shell,
            environment: terminalEnvironment(),
            execName: shellIdiom,
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

    private func terminalEnvironment() -> [String] {
        var values = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        values.append("TERM_PROGRAM=MyIDE")
        values.append("COLORTERM=truecolor")
        return values
    }
}

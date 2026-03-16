import AppKit
import SwiftTerm
import MyIDECore

@MainActor
final class EmbeddedTerminalView: LocalProcessTerminalView {
    private static var didRunAutomationStartCommand = false

    let paneID: String
    private let configuration: TerminalPaneConfiguration
    private var hasStartedProcess = false

    init(paneID: String, configuration: TerminalPaneConfiguration) {
        self.paneID = paneID
        self.configuration = configuration
        super.init(frame: .zero)
        setupAppearance()
        setAccessibilityElement(true)
        setAccessibilityIdentifier("embedded-terminal-\(paneID)")
        setAccessibilityLabel("Embedded Terminal \(paneID)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }

        TerminalAutomationBridge.shared.registerTerminal(self)
        startIfNeeded()
    }

    func terminalSnapshot() -> String {
        String(decoding: getTerminal().getBufferAsData(), as: UTF8.self)
    }

    func terminalLayoutRatios() -> (widthRatio: Double, heightRatio: Double) {
        let terminalFrame = bounds.size
        guard
            let containerSize = enclosingContainerSize(),
            containerSize.width > 0,
            containerSize.height > 0
        else {
            return (1, 1)
        }

        return (
            widthRatio: terminalFrame.width / containerSize.width,
            heightRatio: terminalFrame.height / containerSize.height
        )
    }

    func stopTerminal() {
        terminate()
        TerminalAutomationBridge.shared.unregisterTerminal(paneID: paneID)
    }

    func sendAutomationInput(_ text: String) {
        let bytes = Array(text.utf8)
        send(source: self, data: bytes[...])
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
        runAutomationStartupCommandIfNeeded()
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

    private func runAutomationStartupCommandIfNeeded() {
        guard !Self.didRunAutomationStartCommand else {
            return
        }

        let environment = ProcessInfo.processInfo.environment
        guard let command = environment["MYIDE_AUTOMATION_START_COMMAND"], !command.isEmpty else {
            return
        }

        Self.didRunAutomationStartCommand = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.sendAutomationInput(command + "\r")
        }
    }

    private func enclosingContainerSize() -> CGSize? {
        var current = superview

        while let view = current {
            if view.frame.width > frame.width * 1.02 || view.frame.height > frame.height * 1.02 {
                return view.frame.size
            }
            current = view.superview
        }

        return superview?.frame.size
    }
}

import Foundation

public enum TerminalSessionError: Error, LocalizedError {
    case shellLaunchFailed

    public var errorDescription: String? {
        switch self {
        case .shellLaunchFailed:
            return "Unable to launch interactive shell"
        }
    }
}

public final class TerminalTranscriptBuffer: @unchecked Sendable {
    private enum EscapeState {
        case normal
        case escape
        case csi
        case osc
        case oscEscape
    }

    private let maxCharacters: Int
    private var storage = ""
    private var escapeState: EscapeState = .normal

    public init(maxCharacters: Int = 120_000) {
        self.maxCharacters = maxCharacters
    }

    public var text: String {
        storage
    }

    @discardableResult
    public func append(_ data: Data) -> String {
        process(String(decoding: data, as: UTF8.self))
        normalizePromptArtifacts()
        trimIfNeeded()
        return storage
    }

    private func process(_ string: String) {
        for scalar in string.unicodeScalars {
            switch escapeState {
            case .normal:
                handleNormalScalar(scalar)
            case .escape:
                handleEscapeScalar(scalar)
            case .csi:
                if scalar.value >= 0x40 && scalar.value <= 0x7E {
                    escapeState = .normal
                }
            case .osc:
                if scalar == "\u{07}" {
                    escapeState = .normal
                } else if scalar == "\u{1B}" {
                    escapeState = .oscEscape
                }
            case .oscEscape:
                escapeState = scalar == "\\" ? .normal : .osc
            }
        }
    }

    private func handleNormalScalar(_ scalar: UnicodeScalar) {
        switch scalar {
        case "\u{1B}":
            escapeState = .escape
        case "\r":
            break
        case "\u{08}", "\u{7F}":
            removeLastCharacter()
        case "\n", "\t":
            storage.unicodeScalars.append(scalar)
        default:
            if CharacterSet.controlCharacters.contains(scalar) {
                break
            }
            storage.unicodeScalars.append(scalar)
        }
    }

    private func handleEscapeScalar(_ scalar: UnicodeScalar) {
        if scalar == "[" {
            escapeState = .csi
        } else if scalar == "]" {
            escapeState = .osc
        } else {
            escapeState = .normal
        }
    }

    private func removeLastCharacter() {
        guard !storage.isEmpty else {
            return
        }

        storage.removeLast()
    }

    private func trimIfNeeded() {
        guard storage.count > maxCharacters else {
            return
        }

        let overflow = storage.count - maxCharacters
        storage.removeFirst(overflow)
    }

    private func normalizePromptArtifacts() {
        storage = storage.replacingOccurrences(
            of: #"%\s+MYIDE> "#,
            with: "MYIDE> ",
            options: .regularExpression
        )
    }
}

public final class PTYTerminalSession: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var workingDirectory: String
        public var shellPath: String
        public var prompt: String

        public init(
            workingDirectory: String,
            shellPath: String = "/bin/zsh",
            prompt: String = "MYIDE> "
        ) {
            self.workingDirectory = workingDirectory
            self.shellPath = shellPath
            self.prompt = prompt
        }
    }

    public var onData: (@Sendable (Data) -> Void)?
    public var onExit: (@Sendable (Int32) -> Void)?

    private let configuration: Configuration
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private var process: Process?

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard process == nil else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null", configuration.shellPath, "-f", "-i"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.workingDirectory)

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["PS1"] = configuration.prompt
        environment["PROMPT"] = configuration.prompt
        environment["PROMPT2"] = "> "
        process.environment = environment

        outputPipe.fileHandleForReading.readabilityHandler = { [onData] handle in
            let data = handle.availableData
            if data.isEmpty {
                return
            }
            onData?(data)
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.outputPipe.fileHandleForReading.readabilityHandler = nil
            let exitHandler = self?.onExit
            DispatchQueue.main.async {
                exitHandler?(terminatedProcess.terminationStatus)
            }
        }

        try process.run()
        self.process = process
    }

    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else {
            return
        }
        write(data)
    }

    public func write(_ data: Data) {
        guard process != nil, !data.isEmpty else {
            return
        }

        inputPipe.fileHandleForWriting.writeabilityHandler = nil
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            return
        }
    }

    public func resize(columns: Int, rows: Int) {
        _ = columns
        _ = rows
    }

    public func stop() {
        outputPipe.fileHandleForReading.readabilityHandler = nil

        if let process {
            if process.isRunning {
                process.terminate()
            }
            self.process = nil
        }
    }
}

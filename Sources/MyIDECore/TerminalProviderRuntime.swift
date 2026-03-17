import Foundation
import SwiftTerm

public struct EmbeddedTerminalLaunchPlan: Sendable {
    public var shellPath: String
    public var execName: String
    public var environment: [String]

    public init(shellPath: String, execName: String, environment: [String]) {
        self.shellPath = shellPath
        self.execName = execName
        self.environment = environment
    }
}

public enum TerminalProviderRuntime {
    public static func launchPlan(
        for provider: TerminalProvider,
        shellPath: String
    ) -> EmbeddedTerminalLaunchPlan {
        let resolvedShellPath = shellPath.isEmpty ? "/bin/zsh" : shellPath
        let execName = "-" + URL(fileURLWithPath: resolvedShellPath).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        environment.append("COLORTERM=truecolor")
        environment.append("TERM_PROGRAM=\(termProgramIdentifier(for: provider))")
        return EmbeddedTerminalLaunchPlan(
            shellPath: resolvedShellPath,
            execName: execName,
            environment: environment
        )
    }

    private static func termProgramIdentifier(for provider: TerminalProvider) -> String {
        switch provider {
        case .terminal:
            return "Apple_Terminal"
        case .ghostty:
            return "ghostty"
        case .iterm:
            return "iTerm2"
        }
    }
}

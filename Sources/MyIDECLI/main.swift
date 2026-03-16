import Foundation
import MyIDECore

@main
struct MyIDECLI {
    @MainActor
    static func main() {
        do {
            try CLI(arguments: Array(CommandLine.arguments.dropFirst())).run()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct CLI {
    let arguments: [String]

    @MainActor
    func run() throws {
        guard let command = arguments.first else {
            print(Self.helpText)
            return
        }

        let options = parseOptions(Array(arguments.dropFirst()))

        switch command {
        case "help", "--help", "-h":
            print(Self.helpText)
        case "init":
            let workspaceURL = try workspaceURL(from: options)
            let workspace = Workspace.empty()
            try WorkspaceStore.save(workspace, to: workspaceURL)
            try printJSON(workspace)
        case "show":
            let workspaceURL = try workspaceURL(from: options)
            let workspace = try WorkspaceStore.load(from: workspaceURL)
            try printJSON(workspace)
        case "add-session":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let name = try requiredOption("name", in: options)
            let session = workspace.addSession(named: name)
            try WorkspaceStore.save(workspace, to: workspaceURL)
            try printJSON(session)
        case "add-window":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let title = try requiredOption("title", in: options)
            let window = try workspace.addWindow(toSessionID: sessionID, title: title)
            try WorkspaceStore.save(workspace, to: workspaceURL)
            try printJSON(window)
        case "add-pane":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let pane = try makePane(from: options)
            try workspace.addPane(pane, toSessionID: sessionID, windowID: windowID)
            try WorkspaceStore.save(workspace, to: workspaceURL)
            try printJSON(pane)
        case "run-terminal":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let paneID = try requiredOption("pane-id", in: options)
            let command = try requiredOption("command", in: options)
            let pane = try workspace.pane(sessionID: sessionID, windowID: windowID, paneID: paneID)

            guard let terminal = pane.terminal else {
                throw WorkspaceError.invalidPane("Target pane is not a terminal pane")
            }

            let result = try TerminalCommandRunner.run(command: command, workingDirectory: terminal.workingDirectory)
            try workspace.updatePane(sessionID: sessionID, windowID: windowID, paneID: paneID) { pane in
                pane.terminal?.lastCommand = result.command
                pane.terminal?.lastOutput = result.output
                pane.terminal?.lastExitCode = result.exitCode
            }
            try WorkspaceStore.save(workspace, to: workspaceURL)
            try printJSON(try workspace.pane(sessionID: sessionID, windowID: windowID, paneID: paneID))
        case "refresh-diff":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let paneID = try requiredOption("pane-id", in: options)
            let pane = try workspace.pane(sessionID: sessionID, windowID: windowID, paneID: paneID)

            guard let diff = pane.diff else {
                throw WorkspaceError.invalidPane("Target pane is not a diff pane")
            }

            let output = try UnifiedDiffService.diff(leftPath: diff.leftPath, rightPath: diff.rightPath)
            try workspace.updatePane(sessionID: sessionID, windowID: windowID, paneID: paneID) { pane in
                pane.diff?.lastDiff = output
            }
            try WorkspaceStore.save(workspace, to: workspaceURL)
            try printJSON(try workspace.pane(sessionID: sessionID, windowID: windowID, paneID: paneID))
        case "render-markdown":
            let file = try requiredOption("file", in: options)
            print(try MarkdownPreviewRenderer.html(forMarkdownFileAt: file))
        case "check-terminal-input":
            let typedText = try requiredOption("typed-text", in: options)
            let result = TerminalInteractionHarness.checkClickAndTyping(typedText: typedText)
            try printJSON(result)
        case "ui-check-terminal-input":
            let typedText = try requiredOption("typed-text", in: options)
            let appURL = URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("MyIDESampleMacApp")
            let result = try TerminalUIAutomation.runTerminalClickTypingTest(
                appExecutableURL: appURL,
                typedText: typedText
            )
            try printJSON(result)
        case "ui-run-terminal-command":
            let command = try requiredOption("command", in: options)
            let expectedOutput = try requiredOption("expected-output", in: options)
            let appURL = URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("MyIDESampleMacApp")
            let result = try TerminalUIAutomation.runTerminalCommandTest(
                appExecutableURL: appURL,
                command: command,
                expectedOutput: expectedOutput
            )
            try printJSON(result)
        case "ui-check-terminal-layout":
            let appURL = URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("MyIDESampleMacApp")
            let result = try TerminalUIAutomation.runTerminalLayoutTest(appExecutableURL: appURL)
            try printJSON(result)
        case "debug-terminal-ancestry":
            let appURL = URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("MyIDESampleMacApp")
            let result = try TerminalUIAutomation.debugTerminalAncestry(appExecutableURL: appURL)
            try printJSON(result)
        default:
            throw WorkspaceError.invalidPane("Unknown command: \(command)")
        }
    }

    private func makePane(from options: [String: String]) throws -> WorkspacePane {
        let kindValue = try requiredOption("kind", in: options)
        let title = options["title"] ?? defaultTitle(for: kindValue)

        switch kindValue {
        case "terminal":
            let provider = TerminalProvider(rawValue: options["provider"] ?? "terminal") ?? .terminal
            let cwd = options["working-directory"] ?? FileManager.default.currentDirectoryPath
            return .terminal(title: title, provider: provider, workingDirectory: cwd)
        case "browser":
            return .browser(title: title, urlString: try requiredOption("url", in: options))
        case "diff":
            return .diff(
                title: title,
                leftPath: try requiredOption("left", in: options),
                rightPath: try requiredOption("right", in: options)
            )
        case "markdown":
            return .markdownPreview(title: title, filePath: try requiredOption("file", in: options))
        case "image":
            return .imagePreview(title: title, filePath: try requiredOption("file", in: options))
        default:
            throw WorkspaceError.invalidPane("Unsupported pane kind: \(kindValue)")
        }
    }

    private func defaultTitle(for kindValue: String) -> String {
        switch kindValue {
        case "terminal":
            return "Terminal"
        case "browser":
            return "Browser"
        case "diff":
            return "Diff"
        case "markdown":
            return "Markdown"
        case "image":
            return "Image"
        default:
            return "Pane"
        }
    }

    private func workspaceURL(from options: [String: String]) throws -> URL {
        URL(fileURLWithPath: try requiredOption("workspace", in: options))
    }

    private func parseOptions(_ args: [String]) -> [String: String] {
        var options: [String: String] = [:]
        var index = 0

        while index < args.count {
            let argument = args[index]
            guard argument.hasPrefix("--") else {
                index += 1
                continue
            }

            let key = String(argument.dropFirst(2))
            if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                options[key] = args[index + 1]
                index += 2
            } else {
                options[key] = "true"
                index += 1
            }
        }

        return options
    }

    private func requiredOption(_ key: String, in options: [String: String]) throws -> String {
        guard let value = options[key], !value.isEmpty else {
            throw WorkspaceError.invalidPane("Missing required option --\(key)")
        }

        return value
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WorkspaceError.invalidPane("Unable to encode JSON output")
        }
        print(string)
    }

    private static let helpText = """
    MyIDECLI commands:
      init --workspace PATH
      show --workspace PATH
      add-session --workspace PATH --name NAME
      add-window --workspace PATH --session-id ID --title TITLE
      add-pane --workspace PATH --session-id ID --window-id ID --kind terminal|browser|diff|markdown|image [options]
      run-terminal --workspace PATH --session-id ID --window-id ID --pane-id ID --command COMMAND
      refresh-diff --workspace PATH --session-id ID --window-id ID --pane-id ID
      render-markdown --file PATH
      check-terminal-input --typed-text TEXT
      ui-check-terminal-input --typed-text TEXT
      ui-run-terminal-command --command COMMAND --expected-output TEXT
      ui-check-terminal-layout
    """
}

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
        case "show-session":
            let workspaceURL = try workspaceURL(from: options)
            let workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            guard let session = workspace.session(withID: sessionID) else {
                throw WorkspaceError.sessionNotFound(sessionID)
            }
            try printJSON(session)
        case "add-session":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let name = try requiredOption("name", in: options)
            let session = workspace.addSession(named: name)
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(session)
        case "update-session":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let name = try requiredOption("name", in: options)
            try workspace.updateSession(sessionID: sessionID) { session in
                session.name = name
            }
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            guard let session = workspace.session(withID: sessionID) else {
                throw WorkspaceError.sessionNotFound(sessionID)
            }
            try printJSON(session)
        case "delete-session":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            try workspace.removeSession(sessionID: sessionID)
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(workspace)
        case "add-window":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let title = try requiredOption("title", in: options)
            let window = try workspace.addWindow(toSessionID: sessionID, title: title)
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(window)
        case "show-window":
            let workspaceURL = try workspaceURL(from: options)
            let workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            try printJSON(try workspace.window(sessionID: sessionID, windowID: windowID))
        case "update-window":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let title = try requiredOption("title", in: options)
            try workspace.updateWindow(sessionID: sessionID, windowID: windowID) { window in
                window.title = title
            }
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(try workspace.window(sessionID: sessionID, windowID: windowID))
        case "delete-window":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            try workspace.removeWindow(sessionID: sessionID, windowID: windowID)
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(try sessionPayload(workspace: workspace, sessionID: sessionID))
        case "add-pane":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let pane = try makePane(from: options)
            try workspace.addPane(pane, toSessionID: sessionID, windowID: windowID)
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(pane)
        case "show-pane":
            let workspaceURL = try workspaceURL(from: options)
            let workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let paneID = try requiredOption("pane-id", in: options)
            try printJSON(try workspace.pane(sessionID: sessionID, windowID: windowID, paneID: paneID))
        case "update-pane":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let paneID = try requiredOption("pane-id", in: options)
            try workspace.updatePane(sessionID: sessionID, windowID: windowID, paneID: paneID) { pane in
                try applyPaneUpdates(to: &pane, options: options)
            }
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(try workspace.pane(sessionID: sessionID, windowID: windowID, paneID: paneID))
        case "delete-pane":
            let workspaceURL = try workspaceURL(from: options)
            var workspace = try WorkspaceStore.load(from: workspaceURL)
            let sessionID = try requiredOption("session-id", in: options)
            let windowID = try requiredOption("window-id", in: options)
            let paneID = try requiredOption("pane-id", in: options)
            try workspace.removePane(sessionID: sessionID, windowID: windowID, paneID: paneID)
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(try workspace.window(sessionID: sessionID, windowID: windowID))
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
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
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
            try WorkspaceStore.saveAndNotify(workspace, to: workspaceURL)
            try printJSON(try workspace.pane(sessionID: sessionID, windowID: windowID, paneID: paneID))
        case "render-markdown":
            let file = try requiredOption("file", in: options)
            print(try MarkdownPreviewRenderer.html(forMarkdownFileAt: file))
        case "check-terminal-input":
            let typedText = try requiredOption("typed-text", in: options)
            let result = TerminalInteractionHarness.checkClickAndTyping(typedText: typedText)
            try printJSON(result)
        case "headless-check-terminal-input", "ui-check-terminal-input":
            let typedText = try requiredOption("typed-text", in: options)
            let result = TerminalHeadlessHarness.checkClickAndTyping(typedText: typedText)
            try printJSON(result)
        case "headless-run-terminal-command", "ui-run-terminal-command":
            let command = try requiredOption("command", in: options)
            let expectedOutput = try requiredOption("expected-output", in: options)
            let result = try TerminalHeadlessHarness.runCommand(command, expecting: expectedOutput)
            try printJSON(result)
        case "headless-check-terminal-layout", "ui-check-terminal-layout":
            let result = TerminalHeadlessHarness.checkLayout()
            try printJSON(result)
        case "headless-check-pane-chrome", "ui-check-pane-chrome":
            let result = TerminalHeadlessHarness.checkPaneChrome()
            try printJSON(result)
        case "headless-send-terminal-eot", "ui-send-terminal-eot":
            let result = TerminalHeadlessHarness.checkEndOfTransmissionClosesPane()
            try printJSON(result)
        case "headless-select-preview-file", "ui-select-preview-file":
            let selectedFile = try requiredOption("selected-file", in: options)
            let result = TerminalHeadlessHarness.selectPreviewFile(selectedFile)
            try printJSON(result)
        case "headless-select-diff-file", "ui-select-diff-file":
            let selectedFile = try requiredOption("selected-file", in: options)
            let result = TerminalHeadlessHarness.selectDiffFile(selectedFile)
            try printJSON(result)
        case "headless-check-session-window-semantics":
            let result = try TerminalHeadlessHarness.checkSessionWindowSemantics()
            try printJSON(result)
        case "headless-check-empty-window-switch":
            let result = try TerminalHeadlessHarness.checkSwitchingToEmptyWindowKeepsMainPane()
            try printJSON(result)
        case "headless-check-main-window-reselection-regression":
            let result = try TerminalHeadlessHarness.checkMainWindowReselectionRegression()
            try printJSON(result)
        case "headless-check-add-pane-sheet-scope":
            let result = TerminalHeadlessHarness.checkAddPaneSheetIsScopedPerSessionWindow()
            try printJSON(result)
        case "headless-check-new-session-defaults":
            let result = try TerminalHeadlessHarness.checkNewSessionStartsWithMainWindow()
            try printJSON(result)
        case "headless-check-ime-composition":
            let result = TerminalHeadlessHarness.checkIMECompositionCommit()
            try printJSON(result)
        case "headless-check-delete-line-shortcut":
            let result = try TerminalHeadlessHarness.checkDeleteToBeginningOfLineShortcut()
            try printJSON(result)
        case "headless-check-tmux-split-shortcuts":
            let result = try TerminalHeadlessHarness.checkTmuxSplitShortcuts()
            try printJSON(result)
        case "headless-check-cli-workspace-sync":
            let result = try TerminalHeadlessHarness.checkCLIWorkspaceSync()
            try printJSON(result)
        case "headless-check-pane-split-and-remove":
            let result = try TerminalHeadlessHarness.checkPaneSplitAndRemove()
            try printJSON(result)
        case "headless-check-pane-layout-stability":
            let result = try TerminalHeadlessHarness.checkPaneLayoutStability()
            try printJSON(result)
        case "headless-check-split-presentation-sizing":
            let result = TerminalHeadlessHarness.checkSplitPresentationSizing()
            try printJSON(result)
        case "headless-check-nested-pane-split":
            let result = try TerminalHeadlessHarness.checkNestedPaneSplit()
            try printJSON(result)
        case "headless-check-tmux-split-key-matching":
            let result = try TerminalHeadlessHarness.checkTmuxSplitShortcutKeyMatching()
            try printJSON(result)
        case "headless-check-pane-close-shortcuts":
            let result = try TerminalHeadlessHarness.checkBrowserAndMarkdownPaneCloseShortcuts()
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

    private func applyPaneUpdates(to pane: inout WorkspacePane, options: [String: String]) throws {
        if let title = options["title"], !title.isEmpty {
            pane.title = title
        }

        switch pane.kind {
        case .picker:
            break
        case .terminal:
            guard var terminal = pane.terminal else {
                throw WorkspaceError.invalidPane("Terminal pane is not configured")
            }

            if let providerValue = options["provider"], !providerValue.isEmpty {
                guard let provider = TerminalProvider(rawValue: providerValue) else {
                    throw WorkspaceError.invalidPane("Unsupported terminal provider: \(providerValue)")
                }
                terminal.provider = provider
            }

            if let workingDirectory = options["working-directory"], !workingDirectory.isEmpty {
                terminal.workingDirectory = workingDirectory
            }

            pane.terminal = terminal
        case .browser:
            guard var browser = pane.browser else {
                throw WorkspaceError.invalidPane("Browser pane is not configured")
            }

            if let url = options["url"], !url.isEmpty {
                browser.urlString = url
            }

            pane.browser = browser
        case .diff:
            guard var diff = pane.diff else {
                throw WorkspaceError.invalidPane("Diff pane is not configured")
            }

            if let leftPath = options["left"], !leftPath.isEmpty {
                diff.leftPath = leftPath
            }

            if let rightPath = options["right"], !rightPath.isEmpty {
                diff.rightPath = rightPath
            }

            pane.diff = diff
        case .markdownPreview, .imagePreview:
            guard var preview = pane.preview else {
                throw WorkspaceError.invalidPane("Preview pane is not configured")
            }

            if let file = options["file"], !file.isEmpty {
                preview.filePath = file
            }

            pane.preview = preview
        }
    }

    private func sessionPayload(workspace: Workspace, sessionID: String) throws -> WorkspaceSession {
        guard let session = workspace.session(withID: sessionID) else {
            throw WorkspaceError.sessionNotFound(sessionID)
        }

        return session
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
      show-session --workspace PATH --session-id ID
      add-session --workspace PATH --name NAME
      update-session --workspace PATH --session-id ID --name NAME
      delete-session --workspace PATH --session-id ID
      show-window --workspace PATH --session-id ID --window-id ID
      add-window --workspace PATH --session-id ID --title TITLE
      update-window --workspace PATH --session-id ID --window-id ID --title TITLE
      delete-window --workspace PATH --session-id ID --window-id ID
      show-pane --workspace PATH --session-id ID --window-id ID --pane-id ID
      add-pane --workspace PATH --session-id ID --window-id ID --kind terminal|browser|diff|markdown|image [options]
      update-pane --workspace PATH --session-id ID --window-id ID --pane-id ID [--title TITLE] [--provider PROVIDER] [--working-directory PATH] [--url URL] [--left PATH] [--right PATH] [--file PATH]
      delete-pane --workspace PATH --session-id ID --window-id ID --pane-id ID
      run-terminal --workspace PATH --session-id ID --window-id ID --pane-id ID --command COMMAND
      refresh-diff --workspace PATH --session-id ID --window-id ID --pane-id ID
      render-markdown --file PATH
      check-terminal-input --typed-text TEXT
      headless-check-terminal-input --typed-text TEXT
      headless-run-terminal-command --command COMMAND --expected-output TEXT
      headless-check-terminal-layout
      headless-check-pane-chrome
      headless-send-terminal-eot
      headless-select-preview-file --selected-file PATH
      headless-select-diff-file --selected-file PATH
      headless-check-session-window-semantics
      headless-check-empty-window-switch
      headless-check-main-window-reselection-regression
      headless-check-add-pane-sheet-scope
      headless-check-new-session-defaults
      headless-check-ime-composition
      headless-check-delete-line-shortcut
      headless-check-tmux-split-shortcuts
      headless-check-pane-split-and-remove
      headless-check-pane-layout-stability
      headless-check-split-presentation-sizing
      headless-check-nested-pane-split
      headless-check-tmux-split-key-matching
      headless-check-pane-close-shortcuts
    """
}

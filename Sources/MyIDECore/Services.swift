import Foundation

public struct CommandExecutionResult: Codable, Sendable {
    public var command: String
    public var output: String
    public var exitCode: Int32

    public init(command: String, output: String, exitCode: Int32) {
        self.command = command
        self.output = output
        self.exitCode = exitCode
    }
}

public enum TerminalCommandRunner {
    public static func run(command: String, workingDirectory: String?) throws -> CommandExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        if let workingDirectory, !workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return CommandExecutionResult(command: command, output: output, exitCode: process.terminationStatus)
    }
}

public enum UnifiedDiffService {
    public static func diff(leftPath: String, rightPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
        process.arguments = ["-u", leftPath, rightPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        switch process.terminationStatus {
        case 0, 1:
            return output
        default:
            throw WorkspaceError.invalidPane(output.isEmpty ? "diff command failed" : output)
        }
    }
}

public enum MarkdownPreviewRenderer {
    public static func html(forMarkdownFileAt path: String) throws -> String {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let title = URL(fileURLWithPath: path).lastPathComponent
        return try html(markdown: source, title: title)
    }

    public static func html(markdown: String, title: String) throws -> String {
        let data = try JSONEncoder().encode(markdown)
        let sourceLiteral = String(decoding: data, as: UTF8.self)
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapedTitle)</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: #ffffff; color: #0f172a; }
            #root { padding: 24px; }
            h1, h2, h3 { margin-top: 1.2em; }
            p, li { line-height: 1.6; }
            pre { background: #0f172a; color: #e2e8f0; padding: 16px; border-radius: 12px; overflow: auto; }
            code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            .mermaid { margin: 24px 0; }
          </style>
          <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
          <script type="module">
            import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
            const source = \(sourceLiteral);
            const root = document.getElementById('root');
            root.innerHTML = marked.parse(source);

            root.querySelectorAll('pre code.language-mermaid').forEach((node) => {
              const host = document.createElement('div');
              host.className = 'mermaid';
              host.textContent = node.textContent || '';
              const pre = node.parentElement;
              if (pre && pre.parentElement) {
                pre.parentElement.replaceChild(host, pre);
              }
            });

            mermaid.initialize({ startOnLoad: false, theme: 'neutral' });
            await mermaid.run({ querySelector: '.mermaid' });
          </script>
        </head>
        <body>
          <div id="root"></div>
        </body>
        </html>
        """
    }
}

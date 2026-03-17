import AppKit
import UniformTypeIdentifiers

public enum FileSelectionService {
    public static func chooseFile(
        startingAt path: String? = nil,
        allowedContentTypes: [UTType] = [],
        automatedSelection: String? = nil
    ) -> String? {
        if let automatedSelection, !automatedSelection.isEmpty {
            return automatedSelection
        }

        let environment = ProcessInfo.processInfo.environment
        if let automatedPath = environment["MYIDE_AUTOMATION_SELECTED_FILE"], !automatedPath.isEmpty {
            return automatedPath
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if !allowedContentTypes.isEmpty {
            panel.allowedContentTypes = allowedContentTypes
        }

        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

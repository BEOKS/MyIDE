import Foundation

public enum WorkspaceStore {
    public static let workspaceDidChangeNotification = Notification.Name("myide.workspace-did-change")

    public static func load(from url: URL) throws -> Workspace {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Workspace.self, from: data)
    }

    public static func save(_ workspace: Workspace, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspace)
        try data.write(to: url, options: .atomic)
    }

    public static func saveAndNotify(_ workspace: Workspace, to url: URL) throws {
        try save(workspace, to: url)
        DistributedNotificationCenter.default().postNotificationName(
            workspaceDidChangeNotification,
            object: url.path,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public static func loadOrCreate(at url: URL, seed: @autoclosure () -> Workspace) throws -> Workspace {
        if FileManager.default.fileExists(atPath: url.path) {
            return try load(from: url)
        }

        let workspace = seed()
        try save(workspace, to: url)
        return workspace
    }
}

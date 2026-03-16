import Foundation

public enum TerminalAutomationAction: String, Codable {
    case snapshot
}

public struct TerminalAutomationSnapshotResponse: Codable, Sendable {
    public var paneID: String?
    public var snapshot: String

    public init(paneID: String?, snapshot: String) {
        self.paneID = paneID
        self.snapshot = snapshot
    }
}

import Foundation

public enum TerminalAutomationAction: String, Codable {
    case snapshot
    case layout
    case sendInput
}

public struct TerminalAutomationSnapshotResponse: Codable, Sendable {
    public var paneID: String?
    public var snapshot: String

    public init(paneID: String?, snapshot: String) {
        self.paneID = paneID
        self.snapshot = snapshot
    }
}

public struct TerminalAutomationLayoutResponse: Codable, Sendable {
    public var paneID: String?
    public var widthRatio: Double
    public var heightRatio: Double

    public init(paneID: String?, widthRatio: Double, heightRatio: Double) {
        self.paneID = paneID
        self.widthRatio = widthRatio
        self.heightRatio = heightRatio
    }
}

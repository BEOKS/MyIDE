import Foundation

public enum TerminalShortcutAction: Sendable {
    case deleteToBeginningOfLine

    public var bytes: [UInt8] {
        switch self {
        case .deleteToBeginningOfLine:
            return [0x15] // Ctrl+U
        }
    }
}

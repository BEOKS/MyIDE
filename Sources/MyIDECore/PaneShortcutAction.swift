import AppKit

public enum PaneShortcutAction: Sendable, Equatable {
    case split(axis: PaneSplitAxis)
    case closeSelectedPane

    public static func resolve(event: NSEvent, selectedPaneKind: PaneKind?) -> PaneShortcutAction? {
        let flags = event.modifierFlags.intersection([.control, .shift, .command, .option])
        guard let characters = event.charactersIgnoringModifiers else {
            return nil
        }

        if flags == [.control, .shift] {
            switch characters {
            case "%":
                return .split(axis: .vertical)
            case "\"":
                return .split(axis: .horizontal)
            default:
                return nil
            }
        }

        if flags == [.control],
           characters.lowercased() == "d",
           let selectedPaneKind,
           selectedPaneKind.supportsWindowCloseShortcut {
            return .closeSelectedPane
        }

        return nil
    }
}

public extension PaneKind {
    var supportsWindowCloseShortcut: Bool {
        switch self {
        case .browser, .markdownPreview, .imagePreview, .picker:
            return true
        case .terminal, .diff:
            return false
        }
    }
}

import Foundation

public final class TerminalPaneLifecycleController: @unchecked Sendable {
    private var isTearingDown = false

    public init() {
    }

    public func beginTearDown() {
        isTearingDown = true
    }

    public func shouldPropagateProcessTermination() -> Bool {
        !isTearingDown
    }
}

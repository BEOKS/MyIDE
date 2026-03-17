import Foundation
import AppKit
import MyIDECore

private final class WeakTerminalReference {
    weak var value: EmbeddedTerminalView?

    init(value: EmbeddedTerminalView) {
        self.value = value
    }
}

@MainActor
final class TerminalAutomationBridge {
    static let shared = TerminalAutomationBridge()

    private let notificationName = Notification.Name("myide.terminal-automation.request")
    private var terminals: [String: WeakTerminalReference] = [:]
    private var observer: NSObjectProtocol?

    private init() {
    }

    func startIfNeeded() {
        guard observer == nil, automationDirectory != nil else {
            return
        }

        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { [weak self] in
                self?.handle(notification)
            }
        }
    }

    func registerTerminal(_ terminal: EmbeddedTerminalView) {
        terminals[terminal.paneID] = WeakTerminalReference(value: terminal)
    }

    func unregisterTerminal(paneID: String) {
        terminals.removeValue(forKey: paneID)
    }

    private var automationDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MYIDE_AUTOMATION_DIR"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func handle(_ notification: Notification) {
        guard let automationDirectory else {
            return
        }

        guard
            let userInfo = notification.userInfo,
            let requestID = userInfo["requestID"] as? String,
            let rawAction = userInfo["action"] as? String,
            let action = TerminalAutomationAction(rawValue: rawAction)
        else {
            return
        }

        switch action {
        case .snapshot:
            let paneID = userInfo["paneID"] as? String
            let response = TerminalAutomationSnapshotResponse(
                paneID: paneID,
                snapshot: terminalSnapshot(for: paneID)
            )
            write(response: response, requestID: requestID, automationDirectory: automationDirectory)
        }
    }

    private func terminalSnapshot(for paneID: String?) -> String {
        compactDeadReferences()

        if let paneID, let terminal = terminals[paneID]?.value {
            return terminal.terminalSnapshot()
        }

        if let terminal = terminals.values.compactMap(\.value).first {
            return terminal.terminalSnapshot()
        }

        return ""
    }

    private func compactDeadReferences() {
        terminals = terminals.filter { $0.value.value != nil }
    }

    private func write(response: TerminalAutomationSnapshotResponse, requestID: String, automationDirectory: URL) {
        do {
            try FileManager.default.createDirectory(at: automationDirectory, withIntermediateDirectories: true)
            let url = automationDirectory.appendingPathComponent("\(requestID).json")
            let data = try JSONEncoder().encode(response)
            try data.write(to: url)
        } catch {
        }
    }
}

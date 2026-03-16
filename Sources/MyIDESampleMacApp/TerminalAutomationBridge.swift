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
            let requestID = notification.userInfo?["requestID"] as? String
            let rawAction = notification.userInfo?["action"] as? String
            let paneID = notification.userInfo?["paneID"] as? String
            let input = notification.userInfo?["input"] as? String
            Task { @MainActor in
                self?.handle(requestID: requestID, rawAction: rawAction, paneID: paneID, input: input)
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

    private func handle(requestID: String?, rawAction: String?, paneID: String?, input: String?) {
        guard let automationDirectory else {
            return
        }

        guard
            let requestID,
            let rawAction,
            let action = TerminalAutomationAction(rawValue: rawAction)
        else {
            return
        }

        switch action {
        case .snapshot:
            let response = TerminalAutomationSnapshotResponse(
                paneID: paneID,
                snapshot: terminalSnapshot(for: paneID)
            )
            write(response: response, requestID: requestID, automationDirectory: automationDirectory)
        case .layout:
            let ratios = terminalLayout(for: paneID)
            let response = TerminalAutomationLayoutResponse(
                paneID: paneID,
                widthRatio: ratios.widthRatio,
                heightRatio: ratios.heightRatio
            )
            write(response: response, requestID: requestID, automationDirectory: automationDirectory)
        case .sendInput:
            if let input {
                sendInput(input, to: paneID)
            }
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

    private func terminalLayout(for paneID: String?) -> (widthRatio: Double, heightRatio: Double) {
        compactDeadReferences()

        if let paneID, let terminal = terminals[paneID]?.value {
            return terminal.terminalLayoutRatios()
        }

        if let terminal = terminals.values.compactMap(\.value).first {
            return terminal.terminalLayoutRatios()
        }

        return (0, 0)
    }

    private func sendInput(_ input: String, to paneID: String?) {
        compactDeadReferences()

        if let paneID, let terminal = terminals[paneID]?.value {
            terminal.sendAutomationInput(input)
            return
        }

        terminals.values.compactMap(\.value).first?.sendAutomationInput(input)
    }

    private func compactDeadReferences() {
        terminals = terminals.filter { $0.value.value != nil }
    }

    private func write<Response: Encodable>(response: Response, requestID: String, automationDirectory: URL) {
        do {
            try FileManager.default.createDirectory(at: automationDirectory, withIntermediateDirectories: true)
            let url = automationDirectory.appendingPathComponent("\(requestID).json")
            let data = try JSONEncoder().encode(response)
            try data.write(to: url)
        } catch {
        }
    }
}

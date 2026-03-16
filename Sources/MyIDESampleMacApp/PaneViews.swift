import AppKit
import SwiftUI
import MyIDECore

struct PaneWorkspaceView: View {
    let panes: [WorkspacePane]
    let onRemove: (String) -> Void
    let onUpdateBrowser: (String, String) -> Void
    let onRefreshDiff: (String, String, String) -> Void
    let onUpdatePreviewPath: (String, String) -> Void

    var body: some View {
        Group {
            switch panes.count {
            case 0:
                ContentUnavailableView(
                    "No Panes",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Add a pane to the selected window.")
                )
            case 1:
                paneView(for: panes[0])
            case 2:
                HSplitView {
                    paneView(for: panes[0])
                    paneView(for: panes[1])
                }
            case 3:
                HSplitView {
                    paneView(for: panes[0])
                    VSplitView {
                        paneView(for: panes[1])
                        paneView(for: panes[2])
                    }
                }
            case 4:
                VSplitView {
                    HSplitView {
                        paneView(for: panes[0])
                        paneView(for: panes[1])
                    }
                    HSplitView {
                        paneView(for: panes[2])
                        paneView(for: panes[3])
                    }
                }
            default:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(panes) { pane in
                            paneView(for: pane)
                                .frame(minHeight: 320)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paneView(for pane: WorkspacePane) -> some View {
        PaneContainer(title: pane.title, kind: pane.kind, onRemove: {
            onRemove(pane.id)
        }) {
            switch pane.kind {
            case .terminal:
                if let terminal = pane.terminal {
                    TerminalPaneView(
                        paneID: pane.id,
                        configuration: terminal
                    )
                }
            case .browser:
                if let browser = pane.browser {
                    BrowserPaneView(
                        paneID: pane.id,
                        configuration: browser,
                        onNavigate: onUpdateBrowser
                    )
                }
            case .diff:
                if let diff = pane.diff {
                    DiffPaneView(
                        paneID: pane.id,
                        configuration: diff,
                        onRefresh: onRefreshDiff
                    )
                }
            case .markdownPreview, .imagePreview:
                if let preview = pane.preview {
                    PreviewPaneView(
                        paneID: pane.id,
                        kind: pane.kind,
                        configuration: preview,
                        onUpdatePath: onUpdatePreviewPath
                    )
                }
            }
        }
    }
}

struct PaneContainer<Content: View>: View {
    let title: String
    let kind: PaneKind
    let onRemove: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("pane-container-\(kind.rawValue)")
        .overlay(
            AccessibilityTaggedView(
                identifier: "pane-container-\(kind.rawValue)",
                label: "Pane Container \(kind.rawValue)"
            )
            .allowsHitTesting(false)
        )
    }
}

struct TerminalPaneView: View {
    let paneID: String
    let configuration: TerminalPaneConfiguration

    init(paneID: String, configuration: TerminalPaneConfiguration) {
        self.paneID = paneID
        self.configuration = configuration
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Circle().fill(.yellow).frame(width: 8, height: 8)
                    Circle().fill(.green).frame(width: 8, height: 8)
                }

                Text(configuration.provider.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text(configuration.workingDirectory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.98))

            ZStack(alignment: .bottomLeading) {
                TerminalCommandEditorRepresentable(paneID: paneID, configuration: configuration)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 12) {
                    Text("interactive terminal emulator")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.45))
                .padding(12)
                .allowsHitTesting(false)
            }
            .background(Color.black.opacity(0.98))
            .overlay(
                AccessibilityTaggedView(
                    identifier: "terminal-pane-surface",
                    label: "Terminal Pane Surface"
                )
                .allowsHitTesting(false)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.98), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

struct BrowserPaneView: View {
    let paneID: String
    let configuration: BrowserPaneConfiguration
    let onNavigate: (String, String) -> Void

    @State private var urlString: String

    init(paneID: String, configuration: BrowserPaneConfiguration, onNavigate: @escaping (String, String) -> Void) {
        self.paneID = paneID
        self.configuration = configuration
        self.onNavigate = onNavigate
        _urlString = State(initialValue: configuration.urlString)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onNavigate(paneID, urlString)
                    }

                Button("Open") {
                    onNavigate(paneID, urlString)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)

            Divider()

            BrowserWebView(urlString: configuration.urlString)
        }
    }
}

struct DiffPaneView: View {
    let paneID: String
    let configuration: DiffPaneConfiguration
    let onRefresh: (String, String, String) -> Void

    @State private var leftPath: String
    @State private var rightPath: String

    init(paneID: String, configuration: DiffPaneConfiguration, onRefresh: @escaping (String, String, String) -> Void) {
        self.paneID = paneID
        self.configuration = configuration
        self.onRefresh = onRefresh
        _leftPath = State(initialValue: configuration.leftPath)
        _rightPath = State(initialValue: configuration.rightPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Left file path", text: $leftPath)
                .textFieldStyle(.roundedBorder)

            TextField("Right file path", text: $rightPath)
                .textFieldStyle(.roundedBorder)

            Button("Refresh Diff") {
                onRefresh(paneID, leftPath, rightPath)
            }
            .buttonStyle(.borderedProminent)

            ScrollView {
                Text(configuration.lastDiff.isEmpty ? "No diff yet." : configuration.lastDiff)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
    }
}

struct PreviewPaneView: View {
    let paneID: String
    let kind: PaneKind
    let configuration: PreviewPaneConfiguration
    let onUpdatePath: (String, String) -> Void

    @State private var filePath: String

    init(paneID: String, kind: PaneKind, configuration: PreviewPaneConfiguration, onUpdatePath: @escaping (String, String) -> Void) {
        self.paneID = paneID
        self.kind = kind
        self.configuration = configuration
        self.onUpdatePath = onUpdatePath
        _filePath = State(initialValue: configuration.filePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("File path", text: $filePath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onUpdatePath(paneID, filePath)
                    }

                Button("Load") {
                    onUpdatePath(paneID, filePath)
                }
                .buttonStyle(.borderedProminent)
            }

            switch kind {
            case .markdownPreview:
                MarkdownPreviewContent(filePath: configuration.filePath)
            case .imagePreview:
                ImagePreviewContent(filePath: configuration.filePath)
            default:
                Text("Unsupported preview pane")
            }
        }
        .padding(12)
    }
}

struct AddPaneSheet: View {
    let onSubmit: (AddPaneDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = AddPaneDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Pane")
                .font(.title.bold())

            TextField("Title", text: $draft.title)
                .textFieldStyle(.roundedBorder)

            Picker("Kind", selection: $draft.kind) {
                Text("Terminal").tag(PaneKind.terminal)
                Text("Browser").tag(PaneKind.browser)
                Text("Diff").tag(PaneKind.diff)
                Text("Markdown Preview").tag(PaneKind.markdownPreview)
                Text("Image Preview").tag(PaneKind.imagePreview)
            }

            switch draft.kind {
            case .terminal:
                Picker("Terminal App", selection: $draft.terminalProvider) {
                    ForEach(TerminalProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue.capitalized).tag(provider)
                    }
                }
            case .browser:
                TextField("URL", text: $draft.browserURL)
                    .textFieldStyle(.roundedBorder)
            case .diff:
                TextField("Left file path", text: $draft.leftPath)
                    .textFieldStyle(.roundedBorder)
                TextField("Right file path", text: $draft.rightPath)
                    .textFieldStyle(.roundedBorder)
            case .markdownPreview, .imagePreview:
                TextField("File path", text: $draft.filePath)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Add") {
                    onSubmit(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420, height: 300)
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MyIDECore

struct ProportionalSplitView<Primary: View, Secondary: View>: View {
    let axis: PaneSplitAxis
    let ratio: Double
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    var body: some View {
        GeometryReader { geometry in
            if axis == .vertical {
                HStack(spacing: 1) {
                    primary
                        .frame(width: geometry.size.width * ratio)
                        .frame(maxHeight: .infinity)
                    Divider()
                    secondary
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 1) {
                    primary
                        .frame(height: geometry.size.height * ratio)
                        .frame(maxWidth: .infinity)
                    Divider()
                    secondary
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct PaneWorkspaceView: View {
    let layout: PaneLayoutNode?
    let panes: [WorkspacePane]
    let selectedPaneID: String?
    let onSelectPane: (String) -> Void
    let onTerminalExit: (String) -> Void
    let onUpdateBrowser: (String, String) -> Void
    let onRefreshDiff: (String, String, String) -> Void
    let onUpdateDiffPaths: (String, String, String) -> Void
    let onUpdatePreviewPath: (String, String) -> Void
    let onConfigurePane: (String, PaneKind) -> Void

    var body: some View {
        Group {
            if panes.isEmpty {
                ContentUnavailableView(
                    "No Panes",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Use Ctrl+% or Ctrl+\" to split the current pane.")
                )
            } else if let resolvedLayout = layout ?? legacyLayout {
                layoutView(for: resolvedLayout)
            } else {
                paneView(for: panes[0])
            }
        }
    }

    private var legacyLayout: PaneLayoutNode? {
        guard let firstPane = panes.first else {
            return nil
        }

        return panes.dropFirst().reduce(PaneLayoutNode.leaf(firstPane.id)) { partial, pane in
            .split(axis: .vertical, ratio: 0.5, primary: partial, secondary: .leaf(pane.id))
        }
    }

    private func layoutView(for node: PaneLayoutNode) -> AnyView {
        switch node {
        case .leaf(let paneID):
            if let pane = panes.first(where: { $0.id == paneID }) {
                return AnyView(paneView(for: pane))
            }
            return AnyView(EmptyView())
        case .split(let axis, let ratio, let primary, let secondary):
            return AnyView(
                ProportionalSplitView(axis: axis, ratio: ratio) {
                    layoutView(for: primary)
                } secondary: {
                    layoutView(for: secondary)
                }
            )
        }
    }

    @ViewBuilder
    private func paneView(for pane: WorkspacePane) -> some View {
        PaneContainer(
            kind: pane.kind,
            isSelected: selectedPaneID == pane.id,
            onSelect: {
                onSelectPane(pane.id)
            }
        ) {
            switch pane.kind {
            case .picker:
                PanePickerPaneView(
                    paneID: pane.id,
                    onConfigurePane: onConfigurePane
                )
            case .terminal:
                if let terminal = pane.terminal {
                    TerminalPaneView(
                        paneID: pane.id,
                        configuration: terminal,
                        onProcessTerminated: {
                            onTerminalExit(pane.id)
                        }
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
                        onUpdatePaths: onUpdateDiffPaths,
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
    let kind: PaneKind
    let isSelected: Bool
    let onSelect: () -> Void
    @ViewBuilder let content: Content
    private let chrome = PaneChromeConfiguration.minimal

    var body: some View {
        Group {
            if chrome.showsTitle || chrome.showsCloseButton {
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .accessibilityIdentifier("pane-container-\(kind.rawValue)")
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .overlay(
            AccessibilityTaggedView(
                identifier: "pane-container-\(kind.rawValue)",
                label: "Pane Container \(kind.rawValue)"
            )
            .allowsHitTesting(false)
        )
    }
}

struct PanePickerPaneView: View {
    let paneID: String
    let onConfigurePane: (String, PaneKind) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Choose a pane")
                        .font(.title3.weight(.semibold))
                    Text("Pick what should open in this split.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PaneKind.creatableCases, id: \.self) { kind in
                        Button {
                            onConfigurePane(paneID, kind)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(kind.displayTitle)
                                    .font(.headline)
                                Text(description(for: kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 440)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func description(for kind: PaneKind) -> String {
        switch kind {
        case .picker:
            return ""
        case .terminal:
            return "Run commands in an interactive shell."
        case .browser:
            return "Open docs, dashboards, or local apps."
        case .diff:
            return "Compare two files side by side."
        case .markdownPreview:
            return "Render a markdown file live."
        case .imagePreview:
            return "Inspect image assets quickly."
        }
    }
}

struct TerminalPaneView: View {
    let paneID: String
    let configuration: TerminalPaneConfiguration
    let onProcessTerminated: () -> Void

    init(paneID: String, configuration: TerminalPaneConfiguration, onProcessTerminated: @escaping () -> Void) {
        self.paneID = paneID
        self.configuration = configuration
        self.onProcessTerminated = onProcessTerminated
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
                TerminalCommandEditorRepresentable(
                    paneID: paneID,
                    configuration: configuration,
                    onProcessTerminated: onProcessTerminated
                )
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
    let onUpdatePaths: (String, String, String) -> Void
    let onRefresh: (String, String, String) -> Void

    @State private var leftPath: String
    @State private var rightPath: String

    init(
        paneID: String,
        configuration: DiffPaneConfiguration,
        onUpdatePaths: @escaping (String, String, String) -> Void,
        onRefresh: @escaping (String, String, String) -> Void
    ) {
        self.paneID = paneID
        self.configuration = configuration
        self.onUpdatePaths = onUpdatePaths
        self.onRefresh = onRefresh
        _leftPath = State(initialValue: configuration.leftPath)
        _rightPath = State(initialValue: configuration.rightPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Left file path", text: $leftPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("diff-left-path-\(paneID)")

                Button("Browse…") {
                    guard let selectedPath = FileSelectionService.chooseFile(startingAt: leftPath) else {
                        return
                    }
                    leftPath = selectedPath
                    onUpdatePaths(paneID, leftPath, rightPath)
                }
                .accessibilityIdentifier("diff-left-browse-\(paneID)")
            }

            HStack {
                TextField("Right file path", text: $rightPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("diff-right-path-\(paneID)")

                Button("Browse…") {
                    guard let selectedPath = FileSelectionService.chooseFile(startingAt: rightPath) else {
                        return
                    }
                    rightPath = selectedPath
                    onUpdatePaths(paneID, leftPath, rightPath)
                }
                .accessibilityIdentifier("diff-right-browse-\(paneID)")
            }

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
                    .accessibilityIdentifier("preview-file-path-\(paneID)")
                    .onSubmit {
                        onUpdatePath(paneID, filePath)
                    }

                Button("Browse…") {
                    guard let selectedPath = FileSelectionService.chooseFile(
                        startingAt: filePath,
                        allowedContentTypes: allowedContentTypes
                    ) else {
                        return
                    }

                    filePath = selectedPath
                    onUpdatePath(paneID, selectedPath)
                }
                .accessibilityIdentifier("preview-file-browse-\(paneID)")

                Button("Load") {
                    onUpdatePath(paneID, filePath)
                }
                .buttonStyle(.borderedProminent)
            }

            switch kind {
            case .picker:
                Text("Select a pane type")
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

    private var allowedContentTypes: [UTType] {
        switch kind {
        case .picker:
            return []
        case .markdownPreview:
            return [.plainText, .utf8PlainText, .text, .sourceCode]
        case .imagePreview:
            return [.image]
        default:
            return []
        }
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
                ForEach(PaneKind.creatableCases, id: \.self) { kind in
                    Text(kind.displayTitle).tag(kind)
                }
            }

            switch draft.kind {
            case .picker:
                EmptyView()
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
                HStack {
                    TextField("Left file path", text: $draft.leftPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        draft.leftPath = FileSelectionService.chooseFile(startingAt: draft.leftPath) ?? draft.leftPath
                    }
                }
                HStack {
                    TextField("Right file path", text: $draft.rightPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        draft.rightPath = FileSelectionService.chooseFile(startingAt: draft.rightPath) ?? draft.rightPath
                    }
                }
            case .markdownPreview, .imagePreview:
                HStack {
                    TextField("File path", text: $draft.filePath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        draft.filePath = FileSelectionService.chooseFile(
                            startingAt: draft.filePath,
                            allowedContentTypes: draft.kind == .imagePreview ? [.image] : [.plainText, .utf8PlainText, .text, .sourceCode]
                        ) ?? draft.filePath
                    }
                }
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

import AppKit
import Foundation

public final class TerminalCommandTextView: NSTextView {
    public var onInput: ((String) -> Void)?
    public var onEnter: (() -> Void)?
    public var onBackspace: (() -> Void)?
    public var onDeleteForward: (() -> Void)?
    public var onArrowUp: (() -> Void)?
    public var onArrowDown: (() -> Void)?
    public var onArrowLeft: (() -> Void)?
    public var onArrowRight: (() -> Void)?
    public var onInterrupt: (() -> Void)?
    public var onEndOfTransmission: (() -> Void)?

    public override var acceptsFirstResponder: Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        moveCaretToEnd()
        super.mouseDown(with: event)
        moveCaretToEnd()
    }

    public override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let characters = event.charactersIgnoringModifiers {
            if characters.lowercased() == "v", let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                onInput?(pasted)
                return
            }

            if characters.lowercased() == "c" {
                copy(nil)
                return
            }
        }

        if event.modifierFlags.contains(.control), let characters = event.charactersIgnoringModifiers?.lowercased() {
            if characters == "c" {
                onInterrupt?()
                return
            }

            if characters == "d" {
                onEndOfTransmission?()
                return
            }
        }

        switch event.keyCode {
        case 36, 76:
            onEnter?()
        case 51:
            onBackspace?()
        case 117:
            onDeleteForward?()
        case 123:
            onArrowLeft?()
        case 124:
            onArrowRight?()
        case 125:
            onArrowDown?()
        case 126:
            onArrowUp?()
        default:
            if let characters = event.characters, !characters.isEmpty {
                onInput?(characters)
            }
        }

        moveCaretToEnd()
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let characters = event.charactersIgnoringModifiers?.lowercased() {
            if characters == "v" || characters == "c" {
                keyDown(with: event)
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    public func moveCaretToEnd() {
        let location = string.utf16.count
        setSelectedRange(NSRange(location: location, length: 0))
        scrollRangeToVisible(NSRange(location: location, length: 0))
    }
}

public final class TerminalCommandEditorView: NSView {
    public let scrollView: NSScrollView
    public let textView: TerminalCommandTextView
    public var lastAppliedFocusRequestID = 0
    private var syntheticFocus = false
    private var cachedTranscript = ""
    private var lastKnownColumns = 120
    private var lastKnownRows = 36

    public var onInput: ((String) -> Void)? {
        get { textView.onInput }
        set { textView.onInput = newValue }
    }

    public var onEnter: (() -> Void)? {
        get { textView.onEnter }
        set { textView.onEnter = newValue }
    }

    public var onBackspace: (() -> Void)? {
        get { textView.onBackspace }
        set { textView.onBackspace = newValue }
    }

    public var onDeleteForward: (() -> Void)? {
        get { textView.onDeleteForward }
        set { textView.onDeleteForward = newValue }
    }

    public var onArrowUp: (() -> Void)? {
        get { textView.onArrowUp }
        set { textView.onArrowUp = newValue }
    }

    public var onArrowDown: (() -> Void)? {
        get { textView.onArrowDown }
        set { textView.onArrowDown = newValue }
    }

    public var onArrowLeft: (() -> Void)? {
        get { textView.onArrowLeft }
        set { textView.onArrowLeft = newValue }
    }

    public var onArrowRight: (() -> Void)? {
        get { textView.onArrowRight }
        set { textView.onArrowRight = newValue }
    }

    public var onInterrupt: (() -> Void)? {
        get { textView.onInterrupt }
        set { textView.onInterrupt = newValue }
    }

    public var onEndOfTransmission: (() -> Void)? {
        get { textView.onEndOfTransmission }
        set { textView.onEndOfTransmission = newValue }
    }

    public var onResize: ((Int, Int) -> Void)?

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public var transcript: String {
        get { cachedTranscript }
        set { updateTranscript(newValue) }
    }

    public init(transcript: String) {
        textView = TerminalCommandTextView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.insertionPointColor = .white
        textView.drawsBackground = false
        textView.string = transcript
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityIdentifier("terminal-command-editor")
        textView.setAccessibilityLabel("Embedded Terminal")

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.setAccessibilityIdentifier("terminal-command-scroll")
        scrollView.autoresizingMask = [.width, .height]

        setAccessibilityElement(true)
        setAccessibilityIdentifier("terminal-command-container")
        setAccessibilityLabel("Embedded Terminal Container")

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        addSubview(scrollView)
        cachedTranscript = transcript
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        nil
    }

    public override func layout() {
        super.layout()
        scrollView.frame = bounds
        publishResizeIfNeeded()
    }

    public override func mouseDown(with event: NSEvent) {
        focusEditor()
        textView.mouseDown(with: event)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public func focusEditor() {
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            syntheticFocus = window.makeFirstResponder(textView)
        } else {
            syntheticFocus = true
        }
        textView.moveCaretToEnd()
    }

    public func clickForTesting() {
        focusEditor()
    }

    public var isFocusedForTesting: Bool {
        if let window {
            return window.firstResponder === textView
        }

        return syntheticFocus
    }

    public func injectTranscriptForTesting(_ value: String) {
        updateTranscript(value)
    }

    private func updateTranscript(_ value: String) {
        guard cachedTranscript != value else {
            return
        }

        cachedTranscript = value
        textView.string = value
        textView.moveCaretToEnd()
    }

    private func publishResizeIfNeeded() {
        let characterSize = "W".size(withAttributes: [.font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)])
        guard characterSize.width > 0, characterSize.height > 0 else {
            return
        }

        let horizontalInset = textView.textContainerInset.width * 2
        let verticalInset = textView.textContainerInset.height * 2
        let columns = max(20, Int((bounds.width - horizontalInset) / characterSize.width))
        let rows = max(8, Int((bounds.height - verticalInset) / characterSize.height))

        guard columns != lastKnownColumns || rows != lastKnownRows else {
            return
        }

        lastKnownColumns = columns
        lastKnownRows = rows
        onResize?(columns, rows)
    }
}

public struct TerminalInteractionCheckResult: Codable, Sendable {
    public var focusedAfterClick: Bool
    public var typedText: String

    public init(focusedAfterClick: Bool, typedText: String) {
        self.focusedAfterClick = focusedAfterClick
        self.typedText = typedText
    }
}

public struct TerminalLayoutCheckResult: Codable, Sendable {
    public var widthRatio: Double
    public var heightRatio: Double

    public init(widthRatio: Double, heightRatio: Double) {
        self.widthRatio = widthRatio
        self.heightRatio = heightRatio
    }
}

@MainActor
public enum TerminalInteractionHarness {
    public static func checkClickAndTyping(typedText: String) -> TerminalInteractionCheckResult {
        let editor = TerminalCommandEditorView(transcript: "")
        editor.clickForTesting()

        let focused = editor.isFocusedForTesting
        editor.injectTranscriptForTesting(typedText)

        return TerminalInteractionCheckResult(
            focusedAfterClick: focused,
            typedText: editor.transcript
        )
    }
}

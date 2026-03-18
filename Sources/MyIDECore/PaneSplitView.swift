import AppKit
import SwiftUI

struct InteractivePaneSplitView<Primary: View, Secondary: View>: NSViewRepresentable {
    let axis: PaneSplitAxis
    let identifier: String
    let ratio: Double
    let onRatioCommit: (Double) -> Void
    let primary: Primary
    let secondary: Secondary

    func makeNSView(context: Context) -> InteractivePaneSplitContainerView<Primary, Secondary> {
        InteractivePaneSplitContainerView(
            axis: axis,
            ratio: ratio,
            primary: primary,
            secondary: secondary
        )
    }

    func updateNSView(_ nsView: InteractivePaneSplitContainerView<Primary, Secondary>, context: Context) {
        nsView.axis = axis
        nsView.ratio = ratio
        nsView.onRatioCommit = onRatioCommit
        nsView.dividerIdentifier = identifier
        nsView.update(primary: primary, secondary: secondary)
    }
}

final class InteractivePaneSplitContainerView<Primary: View, Secondary: View>: NSView {
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        if dividerView.frame.contains(point) {
            let dividerPoint = convert(point, to: dividerView)
            if let dividerHit = dividerView.hitTest(dividerPoint) {
                return dividerHit
            }
        }

        if primaryHost.frame.contains(point) {
            let primaryPoint = convert(point, to: primaryHost)
            return primaryHost.hitTest(primaryPoint) ?? primaryHost
        }

        if secondaryHost.frame.contains(point) {
            let secondaryPoint = convert(point, to: secondaryHost)
            return secondaryHost.hitTest(secondaryPoint) ?? secondaryHost
        }

        return nil
    }

    var axis: PaneSplitAxis = .vertical {
        didSet {
            dividerView.axis = axis
            needsLayout = true
        }
    }

    private var storedRatio: Double = 0.5

    var ratio: Double {
        get {
            storedRatio
        }
        set {
            storedRatio = PaneSplitLayoutMetrics.clampedRatio(newValue)
            needsLayout = true
            layoutSubtreeIfNeeded()
            displayIfNeeded()
        }
    }

    var dividerIdentifier: String = "" {
        didSet {
            dividerView.setAccessibilityElement(true)
            dividerView.setAccessibilityIdentifier(dividerIdentifier)
            dividerView.setAccessibilityLabel("Pane Divider")
        }
    }

    var onRatioCommit: ((Double) -> Void)?

    private let primaryHost: NSHostingView<Primary>
    private let secondaryHost: NSHostingView<Secondary>
    private let dividerView = PaneSplitDividerView()
    private let dividerHitThickness: CGFloat = 12

    init(axis: PaneSplitAxis, ratio: Double, primary: Primary, secondary: Secondary) {
        self.axis = axis
        storedRatio = PaneSplitLayoutMetrics.clampedRatio(ratio)
        primaryHost = NSHostingView(rootView: primary)
        secondaryHost = NSHostingView(rootView: secondary)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        dividerView.wantsLayer = true
        dividerView.layer?.zPosition = 1000

        dividerView.axis = axis
        dividerView.onDragChange = { [weak self] locationInWindow in
            self?.handleDragChange(locationInWindow: locationInWindow)
        }
        dividerView.onDragCommit = { [weak self] locationInWindow in
            self?.handleDragCommit(locationInWindow: locationInWindow)
        }

        addSubview(primaryHost)
        addSubview(secondaryHost)
        addSubview(dividerView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(primary: Primary, secondary: Secondary) {
        primaryHost.rootView = primary
        secondaryHost.rootView = secondary
        needsLayout = true
    }

    var dividerFrameInContainerCoordinates: CGRect {
        dividerView.frame
    }

    func hitTestReturnsDivider(at point: CGPoint) -> Bool {
        hitTest(point) is PaneSplitDividerView
    }

    override func layout() {
        super.layout()

        let clampedRatio = PaneSplitLayoutMetrics.clampedRatio(ratio)

        switch axis {
        case .vertical:
            let boundary = bounds.width * clampedRatio
            primaryHost.frame = CGRect(x: 0, y: 0, width: max(boundary, 0), height: bounds.height)
            secondaryHost.frame = CGRect(
                x: boundary,
                y: 0,
                width: max(bounds.width - boundary, 0),
                height: bounds.height
            )
            dividerView.frame = CGRect(
                x: boundary - dividerHitThickness / 2,
                y: 0,
                width: dividerHitThickness,
                height: bounds.height
            )
        case .horizontal:
            let boundary = bounds.height * clampedRatio
            primaryHost.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(boundary, 0))
            secondaryHost.frame = CGRect(
                x: 0,
                y: boundary,
                width: bounds.width,
                height: max(bounds.height - boundary, 0)
            )
            dividerView.frame = CGRect(
                x: 0,
                y: boundary - dividerHitThickness / 2,
                width: bounds.width,
                height: dividerHitThickness
            )
        }
    }

    private func handleDragChange(locationInWindow: CGPoint) {
        ratio = ratio(for: locationInWindow)
    }

    private func handleDragCommit(locationInWindow: CGPoint) {
        let nextRatio = ratio(for: locationInWindow)
        ratio = nextRatio
        onRatioCommit?(nextRatio)
    }

    private func ratio(for locationInWindow: CGPoint) -> Double {
        let point = convert(locationInWindow, from: nil)

        switch axis {
        case .vertical:
            guard bounds.width > 0 else {
                return ratio
            }

            return PaneSplitLayoutMetrics.clampedRatio(Double(point.x / bounds.width))
        case .horizontal:
            guard bounds.height > 0 else {
                return ratio
            }

            return PaneSplitLayoutMetrics.clampedRatio(Double(point.y / bounds.height))
        }
    }
}

final class PaneSplitDividerView: NSView {
    override var isFlipped: Bool {
        true
    }

    var axis: PaneSplitAxis = .vertical {
        didSet {
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    var onDragChange: ((CGPoint) -> Void)?
    var onDragCommit: ((CGPoint) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isDragging = false
    private var isHovered = false
    private let visualThickness: CGFloat = 1

    private var dividerCursor: NSCursor {
        axis == .vertical ? .resizeLeftRight : .resizeUpDown
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: dividerCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        dividerCursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        dividerCursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else {
            return
        }

        isHovered = false
        needsDisplay = true
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isDragging = true
        isHovered = true
        needsDisplay = true
        dividerCursor.set()
        onDragChange?(event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        dividerCursor.set()
        onDragChange?(event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isHovered = bounds.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
        if isHovered {
            dividerCursor.set()
        } else {
            NSCursor.arrow.set()
        }
        onDragCommit?(event.locationInWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let color: NSColor
        if isDragging {
            color = .controlAccentColor
        } else if isHovered {
            color = .controlAccentColor.withAlphaComponent(0.55)
        } else {
            color = .separatorColor
        }

        color.setFill()

        switch axis {
        case .vertical:
            CGRect(
                x: bounds.midX - visualThickness / 2,
                y: 0,
                width: visualThickness,
                height: bounds.height
            ).fill()
        case .horizontal:
            CGRect(
                x: 0,
                y: bounds.midY - visualThickness / 2,
                width: bounds.width,
                height: visualThickness
            ).fill()
        }
    }
}

public struct ProportionalSplitView<Primary: View, Secondary: View>: View {
    let axis: PaneSplitAxis
    let splitPath: PaneLayoutPath
    let ratio: Double
    let onUpdateRatio: (PaneLayoutPath, Double) -> Void
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    public init(
        axis: PaneSplitAxis,
        splitPath: PaneLayoutPath,
        ratio: Double,
        onUpdateRatio: @escaping (PaneLayoutPath, Double) -> Void,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.axis = axis
        self.splitPath = splitPath
        self.ratio = ratio
        self.onUpdateRatio = onUpdateRatio
        self.primary = primary()
        self.secondary = secondary()
    }

    public var body: some View {
        InteractivePaneSplitView(
            axis: axis,
            identifier: "pane-divider-\(splitPath.description)",
            ratio: ratio,
            onRatioCommit: { finalRatio in
                onUpdateRatio(splitPath, finalRatio)
            },
            primary: primary,
            secondary: secondary
        )
    }
}

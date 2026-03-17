import AppKit
import Foundation

public final class TerminalCompositionState: @unchecked Sendable {
    private var markedText: NSAttributedString?
    private var markedSelectionRange = NSRange(location: 0, length: 0)

    public init() {
    }

    public var hasMarkedText: Bool {
        guard let markedText else {
            return false
        }

        return markedText.length > 0
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange) {
        guard let normalized = Self.normalizedAttributedString(from: string), normalized.length > 0 else {
            unmarkText()
            return
        }

        markedText = normalized
        let clampedLocation = min(max(0, selectedRange.location), normalized.length)
        let maxLength = normalized.length - clampedLocation
        let clampedLength = min(max(0, selectedRange.length), maxLength)
        markedSelectionRange = NSRange(location: clampedLocation, length: clampedLength)
    }

    public func committedText(from string: Any) -> String? {
        defer { unmarkText() }
        return Self.normalizedString(from: string)
    }

    public func consumeCommit(from string: Any) -> (text: String, wasComposing: Bool)? {
        let wasComposing = hasMarkedText
        guard let text = committedText(from: string) else {
            return nil
        }

        return (text: text, wasComposing: wasComposing)
    }

    public func unmarkText() {
        markedText = nil
        markedSelectionRange = NSRange(location: 0, length: 0)
    }

    public func selectedRange() -> NSRange {
        hasMarkedText ? markedSelectionRange : NSRange(location: 0, length: 0)
    }

    public func markedRange() -> NSRange {
        guard let markedText, markedText.length > 0 else {
            return NSRange(location: NSNotFound, length: 0)
        }

        return NSRange(location: 0, length: markedText.length)
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let markedText, hasMarkedText else {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            return nil
        }

        let markedRange = self.markedRange()
        let intersection = NSIntersectionRange(range, markedRange)
        guard intersection.location != NSNotFound, intersection.length > 0 else {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            return nil
        }

        actualRange?.pointee = intersection
        return markedText.attributedSubstring(from: intersection)
    }

    private static func normalizedAttributedString(from value: Any) -> NSAttributedString? {
        if let attributed = value as? NSAttributedString {
            return attributed
        }

        guard let string = normalizedString(from: value) else {
            return nil
        }

        return NSAttributedString(string: string)
    }

    private static func normalizedString(from value: Any) -> String? {
        switch value {
        case let attributed as NSAttributedString:
            return attributed.string
        case let string as NSString:
            return string as String
        case let string as String:
            return string
        default:
            return nil
        }
    }
}

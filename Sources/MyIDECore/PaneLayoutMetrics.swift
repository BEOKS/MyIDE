import Foundation

public struct PaneSplitLayoutMetrics: Codable, Sendable, Equatable {
    public static let dividerThickness: Double = 1

    public var primaryExtent: Double
    public var secondaryExtent: Double
    public var dividerOffset: Double

    public init(totalExtent: Double, ratio: Double) {
        let clampedRatio = min(max(ratio, 0), 1)
        let safeTotalExtent = max(totalExtent, 0)
        let primaryExtent = safeTotalExtent * clampedRatio
        let secondaryExtent = max(safeTotalExtent - primaryExtent, 0)

        self.primaryExtent = primaryExtent
        self.secondaryExtent = secondaryExtent
        self.dividerOffset = max(primaryExtent - Self.dividerThickness / 2, 0)
    }
}

public struct PanePickerLayoutMetrics: Codable, Sendable, Equatable {
    public var columnCount: Int
    public var cardMinHeight: Double
    public var contentMaxWidth: Double
    public var horizontalPadding: Double
    public var verticalPadding: Double
    public var headerSpacing: Double
    public var showsSubtitle: Bool
    public var requiresScrolling: Bool

    public init(containerWidth: Double, containerHeight: Double, optionCount: Int = PaneKind.creatableCases.count) {
        let safeWidth = max(containerWidth, 0)
        let safeHeight = max(containerHeight, 0)
        let horizontalPadding = safeWidth < 260 ? 16.0 : 24.0
        let verticalPadding = safeHeight < 220 ? 16.0 : 24.0
        let availableWidth = max(safeWidth - horizontalPadding * 2, 0)
        let compactHeight = safeHeight < 220
        let columnCount = availableWidth < 360 ? 1 : 2
        let cardMinHeight = compactHeight ? 68.0 : 84.0
        let headerSpacing = compactHeight ? 6.0 : 8.0
        let contentMaxWidth = min(availableWidth, columnCount == 1 ? 320.0 : 440.0)
        let rowCount = Int(ceil(Double(max(optionCount, 0)) / Double(columnCount)))
        let headerHeight = compactHeight ? 28.0 : 52.0
        let estimatedContentHeight = headerHeight
            + 20.0
            + Double(rowCount) * cardMinHeight
            + Double(max(rowCount - 1, 0)) * 12.0
            + verticalPadding * 2

        self.columnCount = columnCount
        self.cardMinHeight = cardMinHeight
        self.contentMaxWidth = contentMaxWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.headerSpacing = headerSpacing
        self.showsSubtitle = !compactHeight
        self.requiresScrolling = estimatedContentHeight > safeHeight
    }
}

import Foundation
import CoreGraphics

/// Enumeration for delivery layout metrics.
enum DeliveryLayoutMetrics {
    static let minViewportHeight: CGFloat = 420
    static let viewportTopBottomInsetCompensation: CGFloat = 8

    static let shotListMinHeight: CGFloat = 220
    static let shotListBaseMaxOffset: CGFloat = 220

    static let runEventsHeight: CGFloat = 220
    static let rightPaneScrollMaxHeightCompensation: CGFloat = 0

    static let shotNameColumnWidth: CGFloat = 176
    static let shotRowSpacing: CGFloat = 4
    static let shotRowActionSpacing: CGFloat = 6
    static let shotRowHorizontalPadding: CGFloat = 6
    static let shotRowVerticalPadding: CGFloat = 4

    static let diagnosticsListMaxHeight: CGFloat = 180
    static let diagnosticsMaxRows: Int = 10
}

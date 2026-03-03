import SwiftUI

/// Tunable layout metrics for the root shell (sidebar/titlebar/traffic lights).
enum RootShellMetrics {
    // Split layout bounds.
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 330
    static let detailMinWidth: CGFloat = 780

    // Sidebar top clearance beneath titlebar controls.
    static let sidebarHeaderBaseClearance: CGFloat = 34

    // Sidebar toggle placement in the titlebar region.
    static let sidebarToggleBaseLeading: CGFloat = 90
    static let sidebarToggleBaseTop: CGFloat = 3

    // Shared offset for traffic lights and sidebar toggle.
    static let titlebarControlsOffset = CGSize(width: 8, height: 8)

    // Sidebar toggle chrome and interaction.
    static let sidebarToggleSize = CGSize(width: 28, height: 28)
    static let sidebarToggleCornerRadius: CGFloat = 8
    static let sidebarToggleHoverBackgroundOpacity: Double = 0.13
    static let sidebarToggleHoverAnimationDuration: Double = 0.08

    // Tooltip placement/layering.
    static let sidebarToggleTooltipYOffset: CGFloat = 31
    static let sidebarToggleTooltipZIndex: Double = 1400
    static let sidebarToggleBaseZIndex: Double = 220
    static let sidebarToggleHoveredZIndex: Double = 1200
}

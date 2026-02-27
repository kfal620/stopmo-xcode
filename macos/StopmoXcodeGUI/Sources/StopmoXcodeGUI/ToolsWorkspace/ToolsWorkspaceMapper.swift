import Foundation

enum ToolsWorkspaceMapper {
    static func map(mode: ToolsMode, deliveryPresentation: DeliveryPresentation) -> ToolsWorkspaceContext {
        switch mode {
        case .all:
            return ToolsWorkspaceContext(
                tabs: [.transcode, .matrix, .dpxProres, .diagnostics],
                defaultTab: .transcode,
                headerTitle: "Tools",
                headerSubtitle: "Guided one-off workflows with preflight checks, staged progress, and actionable results.",
                showEmbeddedHeaderChips: true
            )
        case .utilitiesOnly:
            return ToolsWorkspaceContext(
                tabs: [.transcode, .matrix, .diagnostics],
                defaultTab: .transcode,
                headerTitle: "Calibration",
                headerSubtitle: "Utility workflows for single-frame transcode and matrix suggestion, with advanced diagnostics on demand.",
                showEmbeddedHeaderChips: true
            )
        case .deliveryOnly:
            if deliveryPresentation == .diagnosticsOnly {
                return ToolsWorkspaceContext(
                    tabs: [.diagnostics],
                    defaultTab: .diagnostics,
                    headerTitle: "Day Wrap",
                    headerSubtitle: "Delivery diagnostics timeline and operation events.",
                    showEmbeddedHeaderChips: false
                )
            }
            return ToolsWorkspaceContext(
                tabs: [.dpxProres, .diagnostics],
                defaultTab: .dpxProres,
                headerTitle: "Day Wrap",
                headerSubtitle: "Batch DPX to ProRes assembly for end-of-day delivery.",
                showEmbeddedHeaderChips: true
            )
        }
    }
}

import SwiftUI

struct ToolsWorkspaceHeaderView: View {
    let title: String
    let subtitle: String
    let activeTool: ToolKind?
    let lastToolStatus: ToolRunStatus
    let lastToolCompletedLabel: String
    let embedded: Bool
    let showEmbeddedChips: Bool

    var body: some View {
        if !embedded {
            ScreenHeader(title: title, subtitle: subtitle) {
                chips
            }
        } else if showEmbeddedChips {
            chips
        }
    }

    private var chips: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            if let activeTool {
                StatusChip(label: activeTool.rawValue, tone: .warning, density: .compact)
            }
            StatusChip(label: lastToolStatus.label, tone: lastToolStatus.tone, density: .compact)
            StatusChip(label: "Last Run \(lastToolCompletedLabel)", tone: .neutral, density: .compact)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, embedded ? StopmoUI.Spacing.xs : 0)
    }
}

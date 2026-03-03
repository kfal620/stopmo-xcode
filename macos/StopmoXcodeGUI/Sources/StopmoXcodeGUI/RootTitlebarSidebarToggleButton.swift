import SwiftUI

/// Titlebar-positioned sidebar toggle with immediate hover tooltip.
struct RootTitlebarSidebarToggleButton: View {
    let isCollapsed: Bool
    let onToggle: () -> Void
    var onHoverChanged: ((Bool) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    var body: some View {
        Image(systemName: "sidebar.leading")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppVisualTokens.textSecondary)
            .frame(
                width: RootShellMetrics.sidebarToggleSize.width,
                height: RootShellMetrics.sidebarToggleSize.height,
                alignment: .center
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: RootShellMetrics.sidebarToggleCornerRadius,
                    style: .continuous
                )
            )
            .background {
                RoundedRectangle(
                    cornerRadius: RootShellMetrics.sidebarToggleCornerRadius,
                    style: .continuous
                )
                .fill(
                    Color.white.opacity(
                        isHovered ? RootShellMetrics.sidebarToggleHoverBackgroundOpacity : 0
                    )
                )
            }
            .onTapGesture {
                onToggle()
            }
            .onHover { hovering in
                withAnimation(
                    reduceMotion
                        ? nil
                        : .easeOut(duration: RootShellMetrics.sidebarToggleHoverAnimationDuration)
                ) {
                    isHovered = hovering
                }
                onHoverChanged?(hovering)
            }
            .overlay(alignment: .bottom) {
                if isHovered {
                    tooltipBubble
                        .offset(y: RootShellMetrics.sidebarToggleTooltipYOffset)
                }
            }
            .zIndex(isHovered ? RootShellMetrics.sidebarToggleTooltipZIndex : 0)
            .accessibilityElement()
            .accessibilityLabel(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Toggle sidebar"))
            .help(tooltipText)
            .padding(.horizontal, 2)
    }

    private var tooltipText: String {
        isCollapsed ? "Expand sidebar" : "Collapse sidebar"
    }

    // Matches command-bar tooltip bubble style for visual consistency.
    private var tooltipBubble: some View {
        Text(tooltipText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
            .fixedSize(horizontal: true, vertical: true)
            .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 2)
            .allowsHitTesting(false)
    }
}

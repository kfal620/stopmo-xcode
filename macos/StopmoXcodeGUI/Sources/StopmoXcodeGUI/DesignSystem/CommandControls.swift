import SwiftUI

/// Small icon-only action button with explicit accessibility labels/hints.
struct IconActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    let accessibilityHint: String?
    let isDisabled: Bool
    let action: () -> Void

    init(
        systemName: String,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(
                    width: StopmoUI.Width.iconTapTarget,
                    height: StopmoUI.Width.iconTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(accessibilityHint ?? ""))
    }
}

/// Compact visual grouping for clusters of command-bar actions.
struct ToolbarActionCluster<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppVisualTokens.fill(for: .raised))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppVisualTokens.border(for: .raised), lineWidth: 0.75)
        )
    }
}

/// Hover-aware context chip used to show current workspace/config context.
struct CommandContextChip: View {
    let icon: String
    let value: String
    let tooltip: String
    var isPrimary: Bool = false
    var accentColor: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(
                    isPrimary
                        ? (accentColor ?? AppVisualTokens.textPrimary).opacity(isHovered ? 0.26 : 0.18)
                        : AppVisualTokens.fill(for: .panel, emphasized: isHovered)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .stroke(
                    isPrimary
                        ? (accentColor ?? AppVisualTokens.textPrimary).opacity(0.38)
                        : AppVisualTokens.border(for: .panel, chrome: .quiet),
                    lineWidth: 0.75
                )
        )
        .overlay(alignment: .bottom) {
            if isHovered {
                Text(tooltip)
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
                    .offset(y: 28)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: StopmoUI.Motion.hover)) {
                isHovered = hovering
            }
        }
        .zIndex(isHovered ? 80 : 0)
        .help(tooltip)
        .accessibilityLabel(Text(value))
        .accessibilityHint(Text(tooltip))
    }
}

/// Command-bar icon button with optional badge and hover tooltip.
struct CommandIconButton: View {
    let systemImage: String
    let tooltip: String
    let accessibilityLabel: String
    var isDisabled: Bool = false
    var badgeText: String? = nil
    var badgeTone: StatusTone = .warning
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 31, height: 31)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hoverBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(hoverBorder, lineWidth: 0.75)
                    )
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(badgeTone == .danger ? Color.red : Color.orange)
                        )
                        .offset(x: 10, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: StopmoUI.Motion.hover)) {
                isHovered = hovering
            }
        }
        .overlay(alignment: .bottom) {
            if isHovered && !isDisabled {
                tooltipBubble
                    .offset(y: 30)
            }
        }
        .zIndex(isHovered ? 120 : 0)
        .help(tooltip)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(tooltip))
    }

    private var iconColor: Color {
        isDisabled ? Color.secondary.opacity(0.6) : Color.primary
    }

    private var hoverBackground: Color {
        guard !isDisabled else { return .clear }
        return isHovered ? Color.primary.opacity(0.12) : .clear
    }

    private var hoverBorder: Color {
        guard !isDisabled else { return .clear }
        return isHovered ? Color.primary.opacity(0.16) : .clear
    }

    private var tooltipBubble: some View {
        Text(tooltip)
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

import SwiftUI

/// Page-level title/subtitle header used at workspace roots.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Density variant for lifecycle-stage header presentation.
enum StageHeaderStyle {
    case expanded
    case compact
}

/// Branded lifecycle stage header with accent styling and optional trailing content.
struct LifecycleStageHeader<Trailing: View>: View {
    let hub: LifecycleHub
    let title: String
    let subtitle: String?
    let style: StageHeaderStyle
    let showSubtitle: Bool
    @ViewBuilder let trailing: Trailing

    init(
        hub: LifecycleHub,
        title: String,
        subtitle: String? = nil,
        style: StageHeaderStyle = .expanded,
        showSubtitle: Bool = true,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.hub = hub
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.showSubtitle = showSubtitle
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullWidthHeader
            compactFallbackHeader
        }
        .padding(.horizontal, style == .compact ? 9 : 12)
        .padding(.vertical, style == .compact ? 4 : 8)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            hub.accentColor.opacity(style == .compact ? 0.18 : 0.26),
                            hub.accentColor.opacity(style == .compact ? 0.08 : 0.14),
                            AppVisualTokens.panelFill,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .stroke(hub.accentColor.opacity(style == .compact ? 0.28 : 0.38), lineWidth: 0.9)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [hub.accentColor.opacity(0.7), hub.accentColor.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: style == .compact ? 2 : 3)
                .padding(.vertical, 2)
        }
    }

    private var fullWidthHeader: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            stageBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(style == .compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))

                if showSubtitle, let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            trailing
        }
    }

    private var compactFallbackHeader: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            stageBadge
            Text(title)
                .font(style == .compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
            Spacer(minLength: 0)
            trailing
        }
    }

    private var stageBadge: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            Image(systemName: hub.iconName)
            Text(hub.rawValue.uppercased())
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(hub.accentColor)
        .padding(.horizontal, style == .compact ? 7 : 9)
        .padding(.vertical, style == .compact ? 2.5 : 4)
        .background(
            Capsule(style: .continuous)
                .fill(hub.accentColor.opacity(0.24))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(hub.accentColor.opacity(0.55), lineWidth: 0.8)
        )
    }
}

/// Capsule-styled panel selector chip used for sub-panel switching.
struct PanelChipButton: View {
    let label: String
    let iconName: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                Image(systemName: iconName)
                Text(label)
                    .lineLimit(1)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? accentColor : Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected ? accentColor.opacity(0.9) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 0 : 0.75
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Lightweight disclosure label row used for expandable sections.
struct DisclosureToggleLabel: View {
    let title: String
    @Binding var isExpanded: Bool
    var font: Font = .subheadline.weight(.semibold)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Text(title)
                .font(font)
                .foregroundStyle(AppVisualTokens.textSecondary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: StopmoUI.Motion.disclosure)) {
                isExpanded.toggle()
            }
        }
    }
}

/// Interactive disclosure row label with optional trailing controls.
struct DisclosureRowLabel<Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var font: Font = .subheadline.weight(.semibold)
    @ViewBuilder let trailing: Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    init(
        title: String,
        isExpanded: Binding<Bool>,
        font: Font = .subheadline.weight(.semibold),
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.font = font
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            Text(title)
                .font(font)
                .foregroundStyle(isHovered ? AppVisualTokens.textPrimary : AppVisualTokens.textSecondary)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, StopmoUI.Spacing.xs)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.12 : 0.0), lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: StopmoUI.Motion.hover)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: StopmoUI.Motion.disclosure)) {
                isExpanded.toggle()
            }
        }
    }
}

extension DisclosureRowLabel where Trailing == EmptyView {
    init(
        title: String,
        isExpanded: Binding<Bool>,
        font: Font = .subheadline.weight(.semibold)
    ) {
        self.init(title: title, isExpanded: isExpanded, font: font) {
            EmptyView()
        }
    }
}

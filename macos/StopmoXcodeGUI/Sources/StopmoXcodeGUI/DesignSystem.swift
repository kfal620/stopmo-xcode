import SwiftUI

enum StopmoUI {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 12
        static let chip: CGFloat = 7
    }

    enum Width {
        static let keyColumn: CGFloat = 150
        static let formLabel: CGFloat = 220
        static let iconTapTarget: CGFloat = 30
    }
}

private struct HubContentWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var hubContentWidth: CGFloat {
        get { self[HubContentWidthEnvironmentKey.self] }
        set { self[HubContentWidthEnvironmentKey.self] = newValue }
    }
}

extension LifecycleHub {
    var accentColor: Color {
        switch self {
        case .configure:
            return Color.blue
        case .capture:
            return Color.green
        case .triage:
            return Color.orange
        case .deliver:
            return Color.teal
        }
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                accentColor.opacity(0.34),
                accentColor.opacity(0.14),
                Color.secondary.opacity(0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum StatusTone {
    case neutral
    case success
    case warning
    case danger

    var foreground: Color {
        switch self {
        case .neutral:
            return .primary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            return Color.secondary.opacity(0.14)
        case .success:
            return Color.green.opacity(0.16)
        case .warning:
            return Color.orange.opacity(0.18)
        case .danger:
            return Color.red.opacity(0.16)
        }
    }
}

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
        HStack(alignment: .top, spacing: StopmoUI.Spacing.md) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

enum StageHeaderStyle {
    case expanded
    case compact
}

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
        .padding(.horizontal, style == .compact ? 10 : 12)
        .padding(.vertical, style == .compact ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(hub.accentGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .stroke(hub.accentColor.opacity(0.35), lineWidth: 1)
        )
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
        .padding(.horizontal, style == .compact ? 6 : 8)
        .padding(.vertical, style == .compact ? 3 : 4)
        .background(
            Capsule(style: .continuous)
                .fill(hub.accentColor.opacity(0.16))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(hub.accentColor.opacity(0.4), lineWidth: 0.75)
        )
    }
}

enum CardDensity {
    case regular
    case compact
}

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

struct DisclosureToggleLabel: View {
    let title: String
    @Binding var isExpanded: Bool
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack {
            Text(title)
                .font(font)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.12)) {
                isExpanded.toggle()
            }
        }
    }
}

struct AdaptiveColumns<Primary: View, Secondary: View>: View {
    @Environment(\.hubContentWidth) private var hubContentWidth

    let breakpoint: CGFloat
    let spacing: CGFloat
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    init(
        breakpoint: CGFloat = 920,
        spacing: CGFloat = StopmoUI.Spacing.md,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.breakpoint = breakpoint
        self.spacing = spacing
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        Group {
            if hubContentWidth == 0 || hubContentWidth >= breakpoint {
                HStack(alignment: .top, spacing: spacing) {
                    primary
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    secondary
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: spacing) {
                    primary
                    secondary
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct DenseShotRowStyle {
    static let minHeight: CGFloat = 56
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 6
    static let spacing: CGFloat = 6
    static let cornerRadius: CGFloat = 10
}

struct ToolbarStrip<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StopmoUI.Spacing.sm)
        .padding(.vertical, StopmoUI.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }
}

struct MetricWrap<Content: View>: View {
    let minItemWidth: CGFloat
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(
        minItemWidth: CGFloat = 130,
        spacing: CGFloat = StopmoUI.Spacing.xs,
        @ViewBuilder content: () -> Content
    ) {
        self.minItemWidth = minItemWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: minItemWidth), spacing: spacing, alignment: .leading),
            ],
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let density: CardDensity
    let showTitle: Bool
    let showSubtitle: Bool
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        density: CardDensity = .regular,
        showTitle: Bool = true,
        showSubtitle: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.density = density
        self.showTitle = showTitle
        self.showSubtitle = showSubtitle
        self.content = content()
    }

    var body: some View {
        let rowSpacing: CGFloat = density == .compact ? StopmoUI.Spacing.sm : StopmoUI.Spacing.md
        let headerSpacing: CGFloat = density == .compact ? 2 : StopmoUI.Spacing.xxs

        GroupBox {
            VStack(alignment: .leading, spacing: rowSpacing) {
                if showTitle || (showSubtitle && subtitle != nil) {
                    VStack(alignment: .leading, spacing: headerSpacing) {
                        if showTitle {
                            Text(title)
                                .font(density == .compact ? .subheadline.weight(.semibold) : .headline)
                        }
                        if showSubtitle, let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                content
            }
            .padding(.top, density == .compact ? 0 : StopmoUI.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusChip: View {
    let label: String
    let tone: StatusTone
    var density: CardDensity = .regular

    var body: some View {
        Text(label)
            .font((density == .compact ? Font.caption2 : Font.caption).weight(.semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, StopmoUI.Spacing.xs)
            .padding(.vertical, density == .compact ? 2 : StopmoUI.Spacing.xxs)
            .background(tone.background)
            .clipShape(RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous))
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var tone: StatusTone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.sm) {
            Text(key)
                .frame(width: StopmoUI.Width.keyColumn, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(tone == .neutral ? .primary : tone.foreground)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

struct LabeledPathField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    let browseHelp: String
    let browseAction: () -> Void
    let isDisabled: Bool

    init(
        label: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        browseHelp: String,
        isDisabled: Bool,
        browseAction: @escaping () -> Void
    ) {
        self.label = label
        self.placeholder = placeholder
        _text = text
        self.icon = icon
        self.browseHelp = browseHelp
        self.isDisabled = isDisabled
        self.browseAction = browseAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: StopmoUI.Spacing.xs) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                Button(action: browseAction) {
                    Image(systemName: icon)
                }
                .frame(
                    width: StopmoUI.Width.iconTapTarget,
                    height: StopmoUI.Width.iconTapTarget
                )
                .contentShape(Rectangle())
                .help(browseHelp)
                .accessibilityLabel(Text(browseHelp))
                .accessibilityAddTraits(.isButton)
                .disabled(isDisabled)
            }
        }
    }
}

struct EmptyStateCard: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StopmoUI.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
    }
}

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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.75)
        )
    }
}

struct CommandContextChip: View {
    let icon: String
    let value: String
    let tooltip: String

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
                .fill(isHovered ? Color.secondary.opacity(0.22) : Color.secondary.opacity(0.16))
        )
        .overlay(alignment: .top) {
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
                    .offset(y: -28)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .zIndex(isHovered ? 80 : 0)
        .help(tooltip)
        .accessibilityLabel(Text(value))
        .accessibilityHint(Text(tooltip))
    }
}

struct CommandIconButton: View {
    let systemImage: String
    let tooltip: String
    let accessibilityLabel: String
    var isDisabled: Bool = false
    var badgeText: String? = nil
    var badgeTone: StatusTone = .warning
    let action: () -> Void

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
            isHovered = hovering
        }
        .overlay(alignment: .top) {
            if isHovered && !isDisabled {
                tooltipBubble
                    .offset(y: -30)
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

struct LiveStateChip: View {
    let isRunning: Bool
    var runningLabel: String = "Live"
    var idleLabel: String = "Idle"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .scaleEffect(isRunning && isPulsing ? 1.15 : 1.0)
                .opacity(isRunning && isPulsing ? 0.75 : 1.0)
            Text(isRunning ? runningLabel : idleLabel)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isRunning ? Color.green : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(isRunning ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke((isRunning ? Color.green : Color.secondary).opacity(0.25), lineWidth: 0.75)
        )
        .onAppear {
            setPulseAnimation()
        }
        .onChange(of: isRunning) { _, _ in
            setPulseAnimation()
        }
    }

    private var dotColor: Color {
        isRunning ? .green : .secondary
    }

    private func setPulseAnimation() {
        guard isRunning, !reduceMotion else {
            isPulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

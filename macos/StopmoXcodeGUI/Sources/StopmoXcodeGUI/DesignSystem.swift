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

    enum Motion {
        static let hover: Double = 0.14
        static let disclosure: Double = 0.18
    }
}

enum SurfaceLevel {
    case canvas
    case panel
    case card
    case raised

    var nominalFillOpacity: Double {
        switch self {
        case .canvas:
            return 0
        case .panel:
            return 0.045
        case .card:
            return 0.06
        case .raised:
            return 0.08
        }
    }

    var nominalBorderOpacity: Double {
        switch self {
        case .canvas:
            return 0
        case .panel:
            return 0.08
        case .card:
            return 0.084
        case .raised:
            return 0.16
        }
    }
}

enum CardChrome {
    case standard
    case quiet
    case outlined
}

enum SidebarDetailMode {
    case always
    case progressive
    case hidden
}

enum MetadataTone {
    case secondary
    case tertiary
}

enum AppVisualTokens {
    static let backgroundCanvas = LinearGradient(
        colors: [
            Color(red: 0.055, green: 0.072, blue: 0.065),
            Color(red: 0.048, green: 0.06, blue: 0.055),
            Color(red: 0.045, green: 0.055, blue: 0.052),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelFill = Color.white.opacity(0.045)
    static let cardFill = Color.white.opacity(0.06)
    static let raisedFill = Color.white.opacity(0.08)

    static let borderSubtle = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.16)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.58)

    static let shadowSoft = Color.black.opacity(0.14)
    static let shadowRaised = Color.black.opacity(0.22)

    static func stageAccent(hub: LifecycleHub) -> Color {
        hub.accentColor
    }

    static func fill(for level: SurfaceLevel, emphasized: Bool = false) -> Color {
        switch level {
        case .canvas:
            return Color.clear
        case .panel:
            return emphasized ? panelFill.opacity(1.15) : panelFill
        case .card:
            return emphasized ? cardFill.opacity(1.15) : cardFill
        case .raised:
            return emphasized ? raisedFill.opacity(1.1) : raisedFill
        }
    }

    static func border(for level: SurfaceLevel, chrome: CardChrome = .standard) -> Color {
        switch chrome {
        case .quiet:
            return borderSubtle.opacity(0.8)
        case .outlined:
            return borderStrong
        case .standard:
            switch level {
            case .canvas:
                return .clear
            case .panel:
                return borderSubtle
            case .card:
                return borderSubtle.opacity(1.05)
            case .raised:
                return borderStrong.opacity(0.9)
            }
        }
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
                AppVisualTokens.stageAccent(hub: self).opacity(0.32),
                AppVisualTokens.stageAccent(hub: self).opacity(0.13),
                Color.black.opacity(0.12),
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
            return AppVisualTokens.textPrimary
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
            return Color.white.opacity(0.11)
        case .success:
            return Color.green.opacity(0.2)
        case .warning:
            return Color.orange.opacity(0.22)
        case .danger:
            return Color.red.opacity(0.2)
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

struct MetadataTextStyle: ViewModifier {
    let tone: MetadataTone

    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .foregroundStyle(tone == .secondary ? AppVisualTokens.textSecondary : AppVisualTokens.textTertiary)
    }
}

extension View {
    func metadataTextStyle(_ tone: MetadataTone = .secondary) -> some View {
        modifier(MetadataTextStyle(tone: tone))
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
        SurfaceContainer(level: .panel, chrome: .quiet) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                if let title, !title.isEmpty {
                    Text(title)
                        .metadataTextStyle(.tertiary)
                }
                content
            }
            .padding(.horizontal, StopmoUI.Spacing.sm)
            .padding(.vertical, StopmoUI.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct SurfaceContainer<Content: View>: View {
    let level: SurfaceLevel
    let chrome: CardChrome
    let emphasized: Bool
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    init(
        level: SurfaceLevel,
        chrome: CardChrome = .standard,
        emphasized: Bool = false,
        cornerRadius: CGFloat = StopmoUI.Radius.card,
        @ViewBuilder content: () -> Content
    ) {
        self.level = level
        self.chrome = chrome
        self.emphasized = emphasized
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppVisualTokens.fill(for: level, emphasized: emphasized || isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppVisualTokens.border(for: level, chrome: chrome), lineWidth: chrome == .outlined ? 1 : 0.75)
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: StopmoUI.Motion.hover)) {
                    isHovered = hovering
                }
            }
    }

    private var shadowColor: Color {
        if level == .raised || emphasized || isHovered {
            return AppVisualTokens.shadowRaised
        }
        return AppVisualTokens.shadowSoft.opacity(0.65)
    }

    private var shadowRadius: CGFloat {
        if level == .raised || emphasized || isHovered {
            return 8
        }
        return 0
    }

    private var shadowY: CGFloat {
        if level == .raised || emphasized || isHovered {
            return 2
        }
        return 0
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let density: CardDensity
    let surfaceLevel: SurfaceLevel
    let chrome: CardChrome
    let showTitle: Bool
    let showSubtitle: Bool
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        density: CardDensity = .regular,
        surfaceLevel: SurfaceLevel = .panel,
        chrome: CardChrome = .standard,
        showTitle: Bool = true,
        showSubtitle: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.density = density
        self.surfaceLevel = surfaceLevel
        self.chrome = chrome
        self.showTitle = showTitle
        self.showSubtitle = showSubtitle
        self.content = content()
    }

    var body: some View {
        let rowSpacing: CGFloat = density == .compact ? StopmoUI.Spacing.sm : StopmoUI.Spacing.md
        let headerSpacing: CGFloat = density == .compact ? 2 : StopmoUI.Spacing.xxs

        SurfaceContainer(level: surfaceLevel, chrome: chrome, emphasized: chrome == .outlined) {
            VStack(alignment: .leading, spacing: rowSpacing) {
                if showTitle || (showSubtitle && subtitle != nil) {
                    VStack(alignment: .leading, spacing: headerSpacing) {
                        if showTitle {
                            Text(title)
                                .font(density == .compact ? .subheadline.weight(.semibold) : .headline)
                                .foregroundStyle(AppVisualTokens.textPrimary)
                        }
                        if showSubtitle, let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .metadataTextStyle()
                        }
                    }
                }
                content
            }
            .padding(.horizontal, density == .compact ? StopmoUI.Spacing.sm : StopmoUI.Spacing.md)
            .padding(.vertical, density == .compact ? StopmoUI.Spacing.sm : StopmoUI.Spacing.md)
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
            .overlay(
                RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
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
                .foregroundStyle(AppVisualTokens.textSecondary)
            Text(value)
                .foregroundStyle(tone == .neutral ? AppVisualTokens.textPrimary : tone.foreground)
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
        SurfaceContainer(level: .card, chrome: .quiet) {
            Text(message)
                .font(.callout)
                .foregroundStyle(AppVisualTokens.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(StopmoUI.Spacing.md)
        }
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

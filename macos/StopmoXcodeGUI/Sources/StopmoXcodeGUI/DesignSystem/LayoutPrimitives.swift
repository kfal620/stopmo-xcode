import SwiftUI

enum CardDensity {
    case regular
    case compact
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
        let spec = AppVisualTokens.surfaceSpec(
            for: level,
            chrome: chrome,
            emphasized: emphasized,
            isHovered: isHovered
        )

        return content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppVisualTokens.fill(for: level, emphasized: emphasized || isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppVisualTokens.border(for: level, chrome: chrome), lineWidth: spec.borderWidth)
            )
            .shadow(
                color: (spec.usesRaisedShadow ? AppVisualTokens.shadowRaised : AppVisualTokens.shadowSoft).opacity(spec.shadowOpacity),
                radius: spec.shadowRadius,
                x: 0,
                y: spec.shadowY
            )
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: StopmoUI.Motion.hover)) {
                    isHovered = hovering
                }
            }
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

import SwiftUI

/// Density presets used to tune card spacing and typography.
enum CardDensity {
    case regular
    case compact
}

/// Interaction semantics for shared rounded surfaces.
enum SurfaceInteractionStyle {
    case passive
    case control
    case navigation

    var allowsHoverEmphasis: Bool {
        switch self {
        case .passive:
            return false
        case .control, .navigation:
            return true
        }
    }
}

/// Responsive two-column layout that collapses to a vertical stack on narrow widths.
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

/// Standardized right-side inspector surface used by the redesigned workspaces.
struct WorkspaceInspectorPane<Content: View>: View {
    @Environment(\.hubContentWidth) private var hubContentWidth

    let title: String
    let subtitle: String?
    let width: CGFloat
    let interactionStyle: SurfaceInteractionStyle
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        width: CGFloat = 300,
        interactionStyle: SurfaceInteractionStyle = .passive,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.interactionStyle = interactionStyle
        self.content = content()
    }

    var body: some View {
        SectionCard(
            title,
            subtitle: subtitle,
            density: .compact,
            surfaceLevel: .raised,
            chrome: .quiet,
            interactionStyle: interactionStyle,
            showSubtitle: subtitle != nil
        ) {
            content
        }
        .frame(width: pinnedWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var pinnedWidth: CGFloat? {
        guard hubContentWidth == 0 || hubContentWidth >= width + 260 else {
            return nil
        }
        return width
    }
}

/// Expandable bottom dock used for logs, diagnostics, queue, and timeline context.
struct WorkspaceConsoleDock<Content: View, Trailing: View>: View {
    let title: String
    let summary: String?
    @Binding var isExpanded: Bool
    let interactionStyle: SurfaceInteractionStyle
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(
        title: String,
        summary: String? = nil,
        isExpanded: Binding<Bool>,
        interactionStyle: SurfaceInteractionStyle = .passive,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        _isExpanded = isExpanded
        self.interactionStyle = interactionStyle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        SectionCard(
            title,
            subtitle: summary,
            density: .compact,
            surfaceLevel: .panel,
            chrome: .quiet,
            interactionStyle: interactionStyle,
            showSubtitle: false
        ) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: StopmoUI.Spacing.sm) {
                    content
                }
                .padding(.top, StopmoUI.Spacing.xs)
            } label: {
                HStack(spacing: StopmoUI.Spacing.sm) {
                    DisclosureRowLabel(title: title, isExpanded: $isExpanded)
                    Spacer(minLength: 0)
                    trailing
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .metadataTextStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// Shared constants for compact shot-row presentation.
struct DenseShotRowStyle {
    static let minHeight: CGFloat = 76
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 9
    static let spacing: CGFloat = 8
    static let cornerRadius: CGFloat = 12
}

/// Reusable toolbar surface wrapper for grouped top-of-panel controls.
struct ToolbarStrip<Content: View>: View {
    let title: String?
    let interactionStyle: SurfaceInteractionStyle
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        interactionStyle: SurfaceInteractionStyle = .passive,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.interactionStyle = interactionStyle
        self.content = content()
    }

    var body: some View {
        SurfaceContainer(level: .panel, chrome: .quiet, interactionStyle: interactionStyle) {
            VStack(alignment: .leading, spacing: StopmoUI.Spacing.xs) {
                if let title, !title.isEmpty {
                    Text(title)
                        .metadataTextStyle(.tertiary)
                }
                content
            }
            .padding(.horizontal, StopmoUI.Spacing.sm)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Adaptive metrics container built on an `adaptive` lazy grid column.
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

/// Base rounded surface container that applies tokenized fill/border/shadow chrome.
struct SurfaceContainer<Content: View>: View {
    let level: SurfaceLevel
    let chrome: CardChrome
    let emphasized: Bool
    let cornerRadius: CGFloat
    let interactionStyle: SurfaceInteractionStyle
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    init(
        level: SurfaceLevel,
        chrome: CardChrome = .standard,
        emphasized: Bool = false,
        cornerRadius: CGFloat = StopmoUI.Radius.card,
        interactionStyle: SurfaceInteractionStyle = .passive,
        @ViewBuilder content: () -> Content
    ) {
        self.level = level
        self.chrome = chrome
        self.emphasized = emphasized
        self.cornerRadius = cornerRadius
        self.interactionStyle = interactionStyle
        self.content = content()
    }

    var body: some View {
        let spec = AppVisualTokens.surfaceSpec(
            for: level,
            chrome: chrome,
            emphasized: emphasized,
            interactionStyle: interactionStyle,
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
                guard interactionStyle.allowsHoverEmphasis else {
                    return
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: StopmoUI.Motion.hover)) {
                    isHovered = hovering
                }
            }
    }
}

/// Standard section-card shell with optional title/subtitle header.
struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let density: CardDensity
    let surfaceLevel: SurfaceLevel
    let chrome: CardChrome
    let interactionStyle: SurfaceInteractionStyle
    let showTitle: Bool
    let showSubtitle: Bool
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        density: CardDensity = .regular,
        surfaceLevel: SurfaceLevel = .panel,
        chrome: CardChrome = .standard,
        interactionStyle: SurfaceInteractionStyle = .passive,
        showTitle: Bool = true,
        showSubtitle: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.density = density
        self.surfaceLevel = surfaceLevel
        self.chrome = chrome
        self.interactionStyle = interactionStyle
        self.showTitle = showTitle
        self.showSubtitle = showSubtitle
        self.content = content()
    }

    var body: some View {
        let rowSpacing: CGFloat = density == .compact ? StopmoUI.Spacing.sm : StopmoUI.Spacing.md
        let headerSpacing: CGFloat = density == .compact ? 2 : StopmoUI.Spacing.xxs

        SurfaceContainer(
            level: surfaceLevel,
            chrome: chrome,
            emphasized: chrome == .outlined,
            interactionStyle: interactionStyle
        ) {
            VStack(alignment: .leading, spacing: rowSpacing) {
                if showTitle || (showSubtitle && subtitle != nil) {
                    VStack(alignment: .leading, spacing: headerSpacing) {
                        if showTitle {
                            Text(title)
                                .appTextRole(.sectionTitle)
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

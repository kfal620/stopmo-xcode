import SwiftUI

/// Global design-scale constants shared across layout and controls.
enum StopmoUI {
    /// Spacing scale used by the app design system.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
    }

    /// Corner radius scale for cards and chips.
    enum Radius {
        static let card: CGFloat = 12
        static let chip: CGFloat = 7
    }

    /// Common width constants for labels and icon hit targets.
    enum Width {
        static let keyColumn: CGFloat = 150
        static let formLabel: CGFloat = 220
        static let iconTapTarget: CGFloat = 30
    }

    /// Animation timing constants used for interactive affordances.
    enum Motion {
        static let hover: Double = 0.14
        static let disclosure: Double = 0.18
    }
}

/// Layering levels used to derive fill/border/shadow treatment.
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

/// Card border style variants for emphasis control.
enum CardChrome {
    case standard
    case quiet
    case outlined
}

/// Sidebar subtitle visibility strategy based on available width.
enum SidebarDetailMode {
    case always
    case progressive
    case hidden
}

/// Secondary text intensity options for metadata labels.
enum MetadataTone {
    case secondary
    case tertiary
}

/// Semantic status palette used by chips and diagnostics accents.
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

/// Computed visual styling parameters for one rendered surface.
struct SurfaceVisualSpec: Equatable {
    let fillOpacity: Double
    let borderOpacity: Double
    let borderWidth: CGFloat
    let usesRaisedShadow: Bool
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
}

/// Centralized color/gradient/border/shadow tokens for the app shell.
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

    // Shell chrome tokens for command/title bar and split seam compensation.
    static let commandBarBaseOpaque = Color(red: 0.11, green: 0.13, blue: 0.125).opacity(0.94)
    static let commandBarBorder = Color.white.opacity(0.12)
    static let commandBarRightNeutralScrim = LinearGradient(
        colors: [
            Color.clear,
            Color.black.opacity(0.05),
            Color.black.opacity(0.11),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let rootSplitSeam = LinearGradient(
        colors: [
            Color.white.opacity(0.02),
            Color.white.opacity(0.08),
            Color.white.opacity(0.04),
            Color.white.opacity(0.015),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let rootSplitCornerBlend = Color(red: 0.047, green: 0.06, blue: 0.055).opacity(0.96)

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

    static func surfaceSpec(
        for level: SurfaceLevel,
        chrome: CardChrome = .standard,
        emphasized: Bool = false,
        isHovered: Bool = false
    ) -> SurfaceVisualSpec {
        let highlighted = emphasized || isHovered

        let fillOpacity: Double
        switch level {
        case .canvas:
            fillOpacity = 0
        case .panel:
            fillOpacity = highlighted ? 0.045 * 1.15 : 0.045
        case .card:
            fillOpacity = highlighted ? 0.06 * 1.15 : 0.06
        case .raised:
            fillOpacity = highlighted ? 0.08 * 1.1 : 0.08
        }

        let borderOpacity: Double
        switch chrome {
        case .quiet:
            borderOpacity = 0.08 * 0.8
        case .outlined:
            borderOpacity = 0.16
        case .standard:
            switch level {
            case .canvas:
                borderOpacity = 0
            case .panel:
                borderOpacity = 0.08
            case .card:
                borderOpacity = 0.08 * 1.05
            case .raised:
                borderOpacity = 0.16 * 0.9
            }
        }

        let hasRaisedShadow = level == .raised || emphasized || isHovered
        return SurfaceVisualSpec(
            fillOpacity: fillOpacity,
            borderOpacity: borderOpacity,
            borderWidth: chrome == .outlined ? 1 : 0.75,
            usesRaisedShadow: hasRaisedShadow,
            shadowOpacity: hasRaisedShadow ? 1.0 : 0.0,
            shadowRadius: hasRaisedShadow ? 8 : 0,
            shadowY: hasRaisedShadow ? 2 : 0
        )
    }
}

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
        static let hover: Double = 0.10
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
            return 0.03
        case .card:
            return 0.04
        case .raised:
            return 0.055
        }
    }

    var nominalBorderOpacity: Double {
        switch self {
        case .canvas:
            return 0
        case .panel:
            return 0.055
        case .card:
            return 0.0594
        case .raised:
            return 0.10
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
            return Color(red: 0.16, green: 0.43, blue: 0.24)
        case .warning:
            return Color(red: 0.64, green: 0.39, blue: 0.10)
        case .danger:
            return Color(red: 0.66, green: 0.19, blue: 0.20)
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            return Color.black.opacity(0.055)
        case .success:
            return Color(red: 0.76, green: 0.90, blue: 0.80)
        case .warning:
            return Color(red: 0.97, green: 0.89, blue: 0.74)
        case .danger:
            return Color(red: 0.96, green: 0.82, blue: 0.82)
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
            Color(red: 0.97, green: 0.974, blue: 0.978),
            Color(red: 0.956, green: 0.962, blue: 0.972),
            Color(red: 0.942, green: 0.95, blue: 0.964),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelFill = Color.white.opacity(0.72)
    static let cardFill = Color.white.opacity(0.82)
    static let raisedFill = Color.white.opacity(0.94)

    static let borderSubtle = Color.black.opacity(0.08)
    static let borderStrong = Color.black.opacity(0.16)

    static let textPrimary = Color(red: 0.14, green: 0.16, blue: 0.20)
    static let textSecondary = Color(red: 0.34, green: 0.39, blue: 0.45)
    static let textTertiary = Color(red: 0.50, green: 0.55, blue: 0.61)

    static let shadowSoft = Color.black.opacity(0.06)
    static let shadowRaised = Color.black.opacity(0.16)

    // Shell chrome tokens for command/title bar and root framing.
    static let rootShellCornerRadius: CGFloat = 18
    static let rootSidebarTintOverlay = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.19, blue: 0.23).opacity(0.96),
            Color(red: 0.13, green: 0.16, blue: 0.20).opacity(0.98),
            Color(red: 0.11, green: 0.14, blue: 0.18).opacity(0.98),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let rootDetailFrameOpaqueFill = Color(red: 0.985, green: 0.988, blue: 0.992).opacity(0.995)
    static let rootDetailFrameBorder = Color.black.opacity(0.07)
    static let rootDetailFrameShadow = Color.black.opacity(0.12)

    // Existing command-bar tokens.
    static let commandBarBaseOpaque = Color.white.opacity(0.86)
    static let commandBarBorder = Color.black.opacity(0.08)
    static let commandBarRightNeutralScrim = LinearGradient(
        colors: [
            Color.clear,
            Color.black.opacity(0.01),
            Color.black.opacity(0.025),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

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
        interactionStyle: SurfaceInteractionStyle = .passive,
        isHovered: Bool = false
    ) -> SurfaceVisualSpec {
        let highlighted = emphasized || (interactionStyle.allowsHoverEmphasis && isHovered)

        let fillOpacity: Double
        switch level {
        case .canvas:
            fillOpacity = 0
        case .panel:
            fillOpacity = highlighted ? 0.03 * 1.18 : 0.03
        case .card:
            fillOpacity = highlighted ? 0.04 * 1.16 : 0.04
        case .raised:
            fillOpacity = highlighted ? 0.055 * 1.12 : 0.055
        }

        let borderOpacity: Double
        switch chrome {
        case .quiet:
            borderOpacity = 0.055 * 0.8
        case .outlined:
            borderOpacity = 0.10
        case .standard:
            switch level {
            case .canvas:
                borderOpacity = 0
            case .panel:
                borderOpacity = 0.055
            case .card:
                borderOpacity = 0.055 * 1.08
            case .raised:
                borderOpacity = 0.10 * 0.9
            }
        }

        let hasRaisedShadow = level == .raised || emphasized || (interactionStyle.allowsHoverEmphasis && isHovered)
        return SurfaceVisualSpec(
            fillOpacity: fillOpacity,
            borderOpacity: borderOpacity,
            borderWidth: chrome == .outlined ? 0.9 : 0.75,
            usesRaisedShadow: hasRaisedShadow,
            shadowOpacity: hasRaisedShadow ? (level == .raised ? 0.58 : 0.24) : 0.0,
            shadowRadius: hasRaisedShadow ? 5 : 0,
            shadowY: hasRaisedShadow ? 2 : 0
        )
    }
}

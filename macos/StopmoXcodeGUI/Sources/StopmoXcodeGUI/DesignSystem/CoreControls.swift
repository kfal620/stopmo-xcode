import SwiftUI

/// View modifier for consistent secondary/tertiary metadata text styling.
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

enum KeyValueValueStyle {
    case standard
    case path
}

enum KeyValueRowLayout: Equatable {
    case inline
    case stacked
    case adaptive(availableWidth: CGFloat)
}

enum KeyValueRowLayoutResolver {
    static func resolvedLayout(
        requested: KeyValueRowLayout,
        value: String,
        valueStyle: KeyValueValueStyle,
        keyWidth: CGFloat = StopmoUI.Width.keyColumn
    ) -> KeyValueRowLayout {
        switch requested {
        case .inline:
            return .inline
        case .stacked:
            return .stacked
        case .adaptive(let availableWidth):
            guard valueStyle != .path else {
                return .stacked
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let inlineThreshold = keyWidth + 210
            if availableWidth < inlineThreshold || trimmed.count > 42 || trimmed.contains("\n") {
                return .stacked
            }
            return .inline
        }
    }
}

/// Compact semantic badge used for state and health summaries.
struct StatusChip: View {
    let label: String
    let tone: StatusTone
    var density: CardDensity = .regular

    var body: some View {
        Text(label)
            .font((density == .compact ? Font.caption2 : Font.caption).weight(.semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, density == .compact ? 7 : StopmoUI.Spacing.xs)
            .padding(.vertical, density == .compact ? 2 : 3)
            .background(tone.background)
            .clipShape(RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                    .stroke(AppVisualTokens.borderSubtle, lineWidth: 0.5)
            )
    }
}

/// Header chip indicating currently active workspace section.
struct CurrentSectionChip: View {
    let title: String
    let iconName: String
    var accentColor: Color = .accentColor

    var body: some View {
        Label(title, systemImage: iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, StopmoUI.Spacing.sm)
            .padding(.vertical, StopmoUI.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                    .fill(accentColor.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                    .stroke(accentColor.opacity(0.20), lineWidth: 0.75)
            )
            .accessibilityLabel(Text("Current section \(title)"))
    }
}

/// Two-column key/value row used in diagnostics and detail panels.
struct KeyValueRow: View {
    let key: String
    let value: String
    var tone: StatusTone = .neutral
    var layout: KeyValueRowLayout = .adaptive(availableWidth: 520)
    var valueStyle: KeyValueValueStyle = .standard
    var keyWidth: CGFloat = StopmoUI.Width.keyColumn

    var body: some View {
        Group {
            switch resolvedLayout {
            case .inline:
                inlineRow
            case .stacked, .adaptive:
                stackedRow
            }
        }
    }

    private var resolvedLayout: KeyValueRowLayout {
        KeyValueRowLayoutResolver.resolvedLayout(
            requested: layout,
            value: value,
            valueStyle: valueStyle,
            keyWidth: keyWidth
        )
    }

    private var inlineRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.sm) {
            keyText
                .frame(width: keyWidth, alignment: .leading)
            valueText(lineLimit: 1)
        }
        .font(.callout)
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            keyText
            valueText(lineLimit: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keyText: some View {
        Text(key)
            .foregroundStyle(AppVisualTokens.textSecondary)
    }

    private func valueText(lineLimit: Int?) -> some View {
        Text(value)
            .font(valueStyle == .path ? .callout.monospaced() : .callout)
            .foregroundStyle(tone == .neutral ? AppVisualTokens.textPrimary : tone.foreground)
            .lineLimit(lineLimit)
            .truncationMode(valueStyle == .path ? .middle : .tail)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SummaryFact: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    var tone: StatusTone = .neutral
}

struct SummaryFactStrip: View {
    let facts: [SummaryFact]
    var minItemWidth: CGFloat = 112
    var compact: Bool = false

    var body: some View {
        MetricWrap(minItemWidth: minItemWidth, spacing: compact ? StopmoUI.Spacing.xs : StopmoUI.Spacing.sm) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.label)
                        .metadataTextStyle(.tertiary)
                    Text(fact.value)
                        .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                        .foregroundStyle(fact.tone == .neutral ? AppVisualTokens.textPrimary : fact.tone.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, compact ? 1 : 2)
            }
        }
    }
}

struct SummaryLine: View {
    let label: String
    let value: String
    var tone: StatusTone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: StopmoUI.Spacing.xs) {
            Text(label)
                .metadataTextStyle(.tertiary)
            Spacer(minLength: 0)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone == .neutral ? AppVisualTokens.textPrimary : tone.foreground)
        }
    }
}

/// Labeled filesystem path field with browse affordance.
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

/// Reusable empty-state card for sparse panel content.
struct EmptyStateCard: View {
    let message: String

    var body: some View {
        SurfaceContainer(level: .card, chrome: .quiet) {
            Text(message)
                .appTextRole(.support)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(StopmoUI.Spacing.md)
        }
    }
}

/// Animated live/idle status indicator chip for capture surfaces.
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
                .frame(width: 6, height: 6)
                .scaleEffect(isRunning && isPulsing ? 1.15 : 1.0)
                .opacity(isRunning && isPulsing ? 0.75 : 1.0)
            Text(isRunning ? runningLabel : idleLabel)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(isRunning ? Color.green : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(isRunning ? Color.green.opacity(0.12) : Color.black.opacity(0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke((isRunning ? Color.green : AppVisualTokens.borderSubtle).opacity(0.9), lineWidth: 0.75)
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

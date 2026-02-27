import SwiftUI

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
                    .fill(accentColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                    .stroke(accentColor.opacity(0.3), lineWidth: 0.75)
            )
            .accessibilityLabel(Text("Current section \(title)"))
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

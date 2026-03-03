import SwiftUI

/// View rendering root command bar view.
struct RootCommandBarView: View {
    @EnvironmentObject private var state: AppState

    let refreshAction: () async -> Void

    var body: some View {
        ZStack {
            HStack(spacing: StopmoUI.Spacing.sm) {
                currentContextBanner

                Spacer(minLength: 0)

                HStack(spacing: StopmoUI.Spacing.sm) {
                    if state.watchServiceState?.running == true {
                        StatusChip(label: "Watch Running", tone: .success, density: .compact)
                    } else {
                        StatusChip(label: "Watch Stopped", tone: .warning, density: .compact)
                    }

                    ToolbarActionCluster {
                        CommandIconButton(
                            systemImage: "play.fill",
                            tooltip: "Start watch service",
                            accessibilityLabel: "Start Watch",
                            isDisabled: state.isBusy || (state.watchServiceState?.running ?? false)
                        ) {
                            Task { await state.startWatchService() }
                        }

                        CommandIconButton(
                            systemImage: "stop.fill",
                            tooltip: "Stop watch service",
                            accessibilityLabel: "Stop Watch",
                            isDisabled: state.isBusy || !(state.watchServiceState?.running ?? false)
                        ) {
                            Task { await state.stopWatchService() }
                        }

                        CommandIconButton(
                            systemImage: "arrow.clockwise",
                            tooltip: "Refresh current panel",
                            accessibilityLabel: "Refresh",
                            isDisabled: state.isBusy
                        ) {
                            Task { await refreshAction() }
                        }

                        NotificationBellButton()
                    }
                }
            }
            .zIndex(1)

            Text("FrameRelay")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppVisualTokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .allowsHitTesting(false)
                .zIndex(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(AppVisualTokens.commandBarBaseOpaque)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .stroke(AppVisualTokens.commandBarBorder, lineWidth: 0.85)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            state.selectedHub.accentColor.opacity(0.28),
                            state.selectedHub.accentColor.opacity(0.14),
                            state.selectedHub.accentColor.opacity(0.06),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 600)
                .frame(maxHeight: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppVisualTokens.commandBarRightNeutralScrim)
                .frame(width: 360)
                .frame(maxHeight: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous))
        .shadow(color: AppVisualTokens.shadowRaised.opacity(0.46), radius: 7, x: 0, y: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(20)
    }

    private var currentContextBanner: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            Image(systemName: state.selectedHub.iconName)
                .foregroundStyle(state.selectedHub.accentColor)
            Text(state.selectedHub.rawValue)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(AppVisualTokens.textPrimary)
        }
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .fill(state.selectedHub.accentColor.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                .stroke(state.selectedHub.accentColor.opacity(0.4), lineWidth: 0.9)
        )
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityLabel(Text("Current section \(state.selectedHub.rawValue)"))
    }
}

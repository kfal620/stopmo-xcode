import SwiftUI

/// View rendering root command bar view.
struct RootCommandBarView: View {
    @EnvironmentObject private var state: AppState

    let refreshAction: () async -> Void

    var body: some View {
        SurfaceContainer(level: .raised, chrome: .quiet, emphasized: true) {
            HStack(spacing: StopmoUI.Spacing.sm) {
                currentContextBanner

                Spacer(minLength: 0)

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
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            state.selectedHub.accentColor.opacity(0.26),
                            state.selectedHub.accentColor.opacity(0.13),
                            state.selectedHub.accentColor.opacity(0.05),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(maxWidth: 560)
                .mask(
                    RoundedRectangle(cornerRadius: StopmoUI.Radius.card, style: .continuous)
                )
                .allowsHitTesting(false)
        }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

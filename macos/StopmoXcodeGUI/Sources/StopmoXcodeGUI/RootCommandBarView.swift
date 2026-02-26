import SwiftUI

struct RootCommandBarView: View {
    @EnvironmentObject private var state: AppState

    let refreshAction: () async -> Void

    var body: some View {
        SurfaceContainer(level: .raised, chrome: .quiet, emphasized: true) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                projectContextChip

                if state.watchServiceState?.running == true {
                    StatusChip(label: "Watch Running", tone: .success, density: .compact)
                } else {
                    StatusChip(label: "Watch Stopped", tone: .warning, density: .compact)
                }

                Spacer(minLength: 0)

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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(20)
    }

    private var projectContextChip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: StopmoUI.Spacing.xs) {
                CommandContextChip(
                    icon: "map",
                    value: state.hubPanelContextLabel,
                    tooltip: "Current Hub / Panel",
                    isPrimary: true,
                    accentColor: state.selectedHub.accentColor
                )
                CommandContextChip(
                    icon: "doc.text",
                    value: configName,
                    tooltip: "Config Path"
                )
                CommandContextChip(
                    icon: "folder",
                    value: repoRootName,
                    tooltip: "Repo Root"
                )
            }

            HStack(spacing: StopmoUI.Spacing.xs) {
                CommandContextChip(
                    icon: "map",
                    value: state.hubPanelContextLabel,
                    tooltip: "Current Hub / Panel",
                    isPrimary: true,
                    accentColor: state.selectedHub.accentColor
                )
                CommandContextChip(
                    icon: "doc.text",
                    value: configName,
                    tooltip: "Config Path"
                )
            }

            CommandContextChip(
                icon: "map",
                value: state.hubPanelContextLabel,
                tooltip: "Current Hub / Panel",
                isPrimary: true,
                accentColor: state.selectedHub.accentColor
            )
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var repoRootName: String {
        URL(fileURLWithPath: state.repoRoot).lastPathComponent
    }

    private var configName: String {
        URL(fileURLWithPath: state.configPath).lastPathComponent
    }
}

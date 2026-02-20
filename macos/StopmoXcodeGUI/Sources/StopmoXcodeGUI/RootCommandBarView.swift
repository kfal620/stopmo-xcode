import SwiftUI

struct RootCommandBarView: View {
    @EnvironmentObject private var state: AppState

    let refreshAction: () async -> Void

    var body: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            projectContextChip

            if state.watchServiceState?.running == true {
                StatusChip(label: "Watch Running", tone: .success)
            } else {
                StatusChip(label: "Watch Stopped", tone: .warning)
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
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .zIndex(20)
    }

    private var projectContextChip: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            CommandContextChip(
                icon: "folder",
                value: repoRootName,
                tooltip: "Repo Root"
            )
            CommandContextChip(
                icon: "doc.text",
                value: configName,
                tooltip: "Config Path"
            )
            CommandContextChip(
                icon: "map",
                value: state.hubPanelContextLabel,
                tooltip: "Current Hub / Panel"
            )
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var repoRootName: String {
        URL(fileURLWithPath: state.repoRoot).lastPathComponent
    }

    private var configName: String {
        URL(fileURLWithPath: state.configPath).lastPathComponent
    }
}

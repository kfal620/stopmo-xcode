import SwiftUI

/// Compact top toolbar for global app actions and high-signal status context.
struct RootCommandBarView: View {
    @EnvironmentObject private var state: AppState

    let refreshAction: () async -> Void
    var leadingContentInset: CGFloat = 0

    private let chromeShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        HStack(spacing: StopmoUI.Spacing.md) {
            brandCluster

            Divider()
                .frame(height: 24)

            contextCluster

            Spacer(minLength: 0)

            if let status = statusChip {
                StatusChip(label: status.label, tone: status.tone, density: .compact)
            }

            LiveStateChip(
                isRunning: state.watchServiceState?.running ?? false,
                runningLabel: "Watcher Live",
                idleLabel: "Watcher Idle"
            )

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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(.leading, leadingContentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            chromeShape
                .fill(AppVisualTokens.commandBarBaseOpaque)
        )
        .overlay(
            chromeShape
                .stroke(AppVisualTokens.commandBarBorder, lineWidth: 0.85)
        )
        .shadow(color: AppVisualTokens.shadowRaised.opacity(0.32), radius: 12, x: 0, y: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(20)
    }

    private var brandCluster: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                state.selectedHub.accentColor,
                                state.selectedHub.accentColor.opacity(0.66),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: state.selectedHub.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("FrameRelay")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppVisualTokens.textPrimary)
                Text(state.selectedHub.displayTitle)
                    .metadataTextStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var contextCluster: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            CommandContextChip(
                icon: "rectangle.stack",
                value: state.currentPanelLabel,
                tooltip: state.hubPanelContextLabel,
                isPrimary: true,
                accentColor: state.selectedHub.accentColor
            )
            CommandContextChip(
                icon: "folder",
                value: shortWorkspaceLabel,
                tooltip: state.repoRoot
            )
            CommandContextChip(
                icon: "doc.text",
                value: shortConfigLabel,
                tooltip: state.configPath
            )
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var shortWorkspaceLabel: String {
        let trimmed = state.repoRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Workspace" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private var shortConfigLabel: String {
        let trimmed = state.configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Config" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private var statusChip: (label: String, tone: StatusTone)? {
        if state.isBusy {
            return ("Working", .warning)
        }
        if state.errorMessage?.isEmpty == false {
            return ("Needs Attention", .danger)
        }
        let trimmed = state.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Ready" else {
            return nil
        }
        return (trimmed, .neutral)
    }
}

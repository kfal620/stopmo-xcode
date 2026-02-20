import SwiftUI

struct RootSidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: $state.selectedHub) {
            ForEach(LifecycleHub.allCases) { hub in
                NavigationLink(value: hub) {
                    sidebarRow(for: hub)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("stopmo-xcode")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 330)
    }

    private func sidebarRow(for hub: LifecycleHub) -> some View {
        VStack(alignment: .leading, spacing: StopmoUI.Spacing.xxs) {
            HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
                Image(systemName: hub.iconName)
                    .frame(width: 18, alignment: .leading)
                    .foregroundStyle(.secondary)

                Text(hub.rawValue)

                Spacer(minLength: 0)

                if hub == .capture {
                    LiveStateChip(isRunning: state.watchServiceState?.running == true)
                        .help(state.watchServiceState?.running == true ? "Watcher is running" : "Watcher is stopped")
                        .accessibilityLabel(Text(state.watchServiceState?.running == true ? "Watcher live" : "Watcher idle"))
                } else if let badge = sidebarBadge(for: hub) {
                    StatusChip(label: badge.label, tone: badge.tone)
                }
            }

            Text(hub.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func sidebarBadge(for hub: LifecycleHub) -> SidebarBadge? {
        switch hub {
        case .triage:
            let failed = state.queueSnapshot?.counts["failed"] ?? 0
            if failed > 0 {
                return SidebarBadge(label: "\(failed)!", tone: .danger)
            }
            let warnings = state.logsDiagnostics?.warnings.count ?? 0
            if warnings > 0 {
                return SidebarBadge(label: "\(warnings)", tone: .warning)
            }
            return nil
        case .deliver:
            let runs = state.historySummary?.count ?? 0
            if runs > 0 {
                return SidebarBadge(label: "\(runs)", tone: .neutral)
            }
            return nil
        default:
            return nil
        }
    }
}

private struct SidebarBadge {
    let label: String
    let tone: StatusTone
}

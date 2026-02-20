import SwiftUI

struct RootSidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: $state.selectedSection) {
            ForEach(AppSection.allCases) { section in
                NavigationLink(value: section) {
                    sidebarRow(for: section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("stopmo-xcode")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
    }

    private func sidebarRow(for section: AppSection) -> some View {
        HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
            Image(systemName: section.iconName)
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(section.rawValue)

            Spacer(minLength: 0)

            if section == .liveMonitor {
                LiveStateChip(isRunning: state.watchServiceState?.running == true)
                    .help(state.watchServiceState?.running == true ? "Watcher is running" : "Watcher is stopped")
                    .accessibilityLabel(Text(state.watchServiceState?.running == true ? "Watcher live" : "Watcher idle"))
            } else if let badge = sidebarBadge(for: section) {
                StatusChip(label: badge.label, tone: badge.tone)
            }
        }
        .padding(.vertical, 2)
    }

    private func sidebarBadge(for section: AppSection) -> SidebarBadge? {
        switch section {
        case .queue:
            let failed = state.queueSnapshot?.counts["failed"] ?? 0
            if failed > 0 {
                return SidebarBadge(label: "\(failed)!", tone: .danger)
            }
            return nil
        case .logs:
            let warnings = state.logsDiagnostics?.warnings.count ?? 0
            if warnings > 0 {
                return SidebarBadge(label: "\(warnings)", tone: .warning)
            }
            return nil
        case .history:
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

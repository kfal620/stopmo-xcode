import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        sidebarRow(for: section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("stopmo-xcode")
        } detail: {
            VStack(spacing: 0) {
                commandBar
                Divider()
                detailView
            }
        }
        .onAppear {
            state.setMonitoringEnabled(for: state.selectedSection)
        }
        .onChange(of: state.selectedSection) { _, next in
            state.setMonitoringEnabled(for: next)
        }
        .alert(item: $state.presentedError) { presented in
            Alert(
                title: Text(presented.title),
                message: Text(presented.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay(alignment: .bottomLeading) {
            statusBar
                .padding(.leading, 12)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch state.selectedSection {
        case .setup:
            SetupView()
        case .project:
            ProjectView()
        case .liveMonitor:
            LiveMonitorView()
        case .shots:
            ShotsView()
        case .queue:
            QueueView()
        case .tools:
            ToolsView()
        case .logs:
            LogsDiagnosticsView()
        case .history:
            HistoryView()
        }
    }

    private var commandBar: some View {
        HStack(spacing: StopmoUI.Spacing.sm) {
            projectContextChip

            if state.watchServiceState?.running == true {
                StatusChip(label: "Watch Running", tone: .success)
            } else {
                StatusChip(label: "Watch Stopped", tone: .warning)
            }

            Spacer(minLength: 0)

            Button("Start Watch") {
                Task { await state.startWatchService() }
            }
            .disabled(state.isBusy || (state.watchServiceState?.running ?? false))

            Button("Stop Watch") {
                Task { await state.stopWatchService() }
            }
            .disabled(state.isBusy || !(state.watchServiceState?.running ?? false))

            Button("Refresh") {
                Task { await refreshSelectedSection() }
            }
            .disabled(state.isBusy)

            Button("Validate Config") {
                Task { await state.validateConfig() }
            }
            .disabled(state.isBusy)

            Button("Check Runtime Health") {
                Task { await state.refreshHealth() }
            }
            .disabled(state.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var projectContextChip: some View {
        HStack(spacing: StopmoUI.Spacing.xs) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(repoRootName)
                .lineLimit(1)
                .truncationMode(.middle)
            Divider()
                .frame(height: 12)
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(configName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: StopmoUI.Radius.chip, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
        )
        .frame(maxWidth: 430, alignment: .leading)
    }

    private func sidebarRow(for section: AppSection) -> some View {
        HStack(alignment: .top, spacing: StopmoUI.Spacing.sm) {
            Image(systemName: section.iconName)
                .frame(width: 18, alignment: .leading)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.rawValue)
                Text(section.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let badge = sidebarBadge(for: section) {
                StatusChip(label: badge.label, tone: badge.tone)
            }
        }
        .padding(.vertical, 2)
    }

    private func sidebarBadge(for section: AppSection) -> SidebarBadge? {
        switch section {
        case .liveMonitor:
            if state.watchServiceState?.running == true {
                return SidebarBadge(label: "RUN", tone: .success)
            }
            return nil
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

    private func refreshSelectedSection() async {
        switch state.selectedSection {
        case .setup:
            await state.refreshHealth()
        case .project:
            await state.loadConfig()
        case .liveMonitor, .queue, .shots:
            await state.refreshLiveData()
        case .tools:
            await state.refreshLiveData()
        case .logs:
            await state.refreshLogsDiagnostics()
        case .history:
            await state.refreshHistory()
        }
    }

    private var repoRootName: String {
        URL(fileURLWithPath: state.repoRoot).lastPathComponent
    }

    private var configName: String {
        URL(fileURLWithPath: state.configPath).lastPathComponent
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(state.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = state.errorMessage, !error.isEmpty {
                Text("•")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    state.presentError(title: "Last Error", message: error)
                } label: {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize(horizontal: true, vertical: true)
    }
}

private struct SidebarBadge {
    let label: String
    let tone: StatusTone
}

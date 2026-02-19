import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $state.selectedSection) { section in
                Text(section.rawValue)
                    .tag(Optional(section))
            }
            .navigationTitle("stopmo-xcode")
        } detail: {
            switch state.selectedSection ?? .setup {
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
                PlaceholderView(title: "Tools", description: "Phase 6: transcode-one, matrix suggestion, dpx-to-prores.")
            case .logs:
                PlaceholderView(title: "Logs & Diagnostics", description: "Phase 7: structured logs and diagnostics.")
            case .history:
                PlaceholderView(title: "History", description: "Phase 7: operation history and reproducibility index.")
            }
        }
        .onAppear {
            state.setMonitoringEnabled(for: state.selectedSection)
        }
        .onChange(of: state.selectedSection) { _, next in
            state.setMonitoringEnabled(for: next)
        }
        .overlay(alignment: .bottomLeading) {
            statusBar
        }
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
                Divider()
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }
}

private struct PlaceholderView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .bold()
            Text(description)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}

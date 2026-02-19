import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Text(section.rawValue)
                    }
                }
            }
            .navigationTitle("stopmo-xcode")
        } detail: {
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

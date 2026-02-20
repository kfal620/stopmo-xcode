import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            RootSidebarView()
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        RootCommandBarView {
                            await refreshSelectedSection()
                        }
                        Divider()
                    }
                }
                .navigationSplitViewColumnWidth(min: 760, ideal: 980)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            state.setMonitoringEnabled(for: state.selectedSection)
            state.reduceMotionEnabled = reduceMotion
        }
        .onChange(of: state.selectedSection) { _, next in
            state.setMonitoringEnabled(for: next)
        }
        .onChange(of: reduceMotion) { _, next in
            state.reduceMotionEnabled = next
        }
        .alert(item: $state.presentedError) { presented in
            Alert(
                title: Text(presented.title),
                message: Text(presented.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .notificationPresentation()
        .overlay(alignment: .bottomLeading) {
            RootStatusBarView()
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
}

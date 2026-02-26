import SwiftUI

private struct RootDetailWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detailContentWidth: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            RootSidebarView()
        } detail: {
            detailView
                .environment(\.hubContentWidth, detailContentWidth)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: RootDetailWidthPreferenceKey.self,
                            value: proxy.size.width
                        )
                    }
                )
                .onPreferenceChange(RootDetailWidthPreferenceKey.self) { width in
                    detailContentWidth = width
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        RootCommandBarView {
                            await state.refreshCurrentSelection()
                        }
                        Divider()
                    }
                }
                .navigationSplitViewColumnWidth(min: 780, ideal: 1120)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            state.updateMonitoringForSelection()
            state.reduceMotionEnabled = reduceMotion
        }
        .onChange(of: state.selectedHub) { _, _ in
            state.updateMonitoringForSelection()
        }
        .onChange(of: state.selectedTriagePanel) { _, _ in
            state.updateMonitoringForSelection()
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
        switch state.selectedHub {
        case .configure:
            ConfigureHubView()
        case .capture:
            CaptureHubView()
        case .triage:
            TriageHubView()
        case .deliver:
            DeliverHubView()
        }
    }
}

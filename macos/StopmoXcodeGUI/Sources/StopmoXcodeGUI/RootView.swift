import SwiftUI

/// Environment/preference key for root detail width preference key.
private struct RootDetailWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// View rendering root view.
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
                .background {
                    ZStack {
                        AppVisualTokens.backgroundCanvas
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.clear,
                            ],
                            center: .topLeading,
                            startRadius: 20,
                            endRadius: 520
                        )
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RootDetailWidthPreferenceKey.self,
                                value: proxy.size.width
                            )
                        }
                    }
                }
                .onPreferenceChange(RootDetailWidthPreferenceKey.self) { width in
                    detailContentWidth = width
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: StopmoUI.Spacing.xxs) {
                        RootCommandBarView {
                            await state.refreshCurrentSelection()
                        }
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
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

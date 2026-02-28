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
    @State private var sidebarWidth: CGFloat = 0

    var body: some View {
        NavigationSplitView {
            RootSidebarView()
                .onPreferenceChange(SidebarWidthPreferenceKey.self) { width in
                    sidebarWidth = width
                }
        } detail: {
            VStack(spacing: 0) {
                RootCommandBarView {
                    await state.refreshCurrentSelection()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .zIndex(120)

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
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
                .ignoresSafeArea(edges: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationSplitViewColumnWidth(min: 780, ideal: 1120)
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .topLeading) {
            splitSeamOverlay
        }
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

    private var splitSeamOverlay: some View {
        GeometryReader { proxy in
            if sidebarWidth > 0 {
                let seamX = max(0, min(proxy.size.width, sidebarWidth))
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(AppVisualTokens.rootSplitSeam)
                        .frame(width: 1)
                        .frame(height: max(0, proxy.size.height - 12))
                        .offset(x: seamX - 0.5, y: 8)

                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppVisualTokens.rootSplitCornerBlend)
                        .frame(width: 18, height: 18)
                        .offset(x: seamX - 9, y: proxy.size.height - 18)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

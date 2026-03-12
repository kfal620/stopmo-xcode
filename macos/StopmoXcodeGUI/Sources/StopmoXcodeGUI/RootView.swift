import SwiftUI
import AppKit

/// Preference key used to propagate root detail content width.
private struct RootDetailWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Coordinates root split layout and top-level shell overlays.
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var detailContentWidth: CGFloat = 0
    @State private var sidebarWidth: CGFloat = 208
    @State private var lastExpandedSidebarWidth: CGFloat = 208
    @State private var sidebarDragBaseWidth: CGFloat?
    @State private var isSidebarToggleHovered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            RootSidebarView(
                topContentInset: RootShellMetrics.sidebarHeaderBaseClearance + RootShellMetrics.titlebarControlsOffset.height
            )
            .frame(width: sidebarWidth)
            .opacity(sidebarWidth > 1 ? 1 : 0)
            .allowsHitTesting(sidebarWidth > 1)
            .clipped()

            if sidebarWidth > 1 {
                sidebarResizeHandle
            }

            detailShell
                .frame(
                    minWidth: RootShellMetrics.detailMinWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        .background {
            AppVisualTokens.backgroundCanvas
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .overlay(alignment: .topLeading) {
            RootTitlebarSidebarToggleButton(
                isCollapsed: sidebarWidth <= 1,
                onToggle: toggleSidebarCollapse,
                onHoverChanged: { isSidebarToggleHovered = $0 }
            )
            .padding(
                .leading,
                RootShellMetrics.sidebarToggleBaseLeading + RootShellMetrics.titlebarControlsOffset.width
            )
            .padding(
                .top,
                RootShellMetrics.sidebarToggleBaseTop + RootShellMetrics.titlebarControlsOffset.height
            )
            .ignoresSafeArea(edges: .top)
            .zIndex(
                isSidebarToggleHovered
                    ? RootShellMetrics.sidebarToggleHoveredZIndex
                    : RootShellMetrics.sidebarToggleBaseZIndex
            )
        }
        .background {
            RootWindowChromeConfigurator(titlebarControlsOffset: RootShellMetrics.titlebarControlsOffset)
        }
    }

    private var detailShell: some View {
        VStack(spacing: StopmoUI.Spacing.sm) {
            RootCommandBarView(
                refreshAction: {
                    await state.refreshCurrentSelection()
                },
                leadingContentInset: collapsedCommandBarLeadingInset
            )
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .zIndex(120)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .environment(\.hubContentWidth, detailContentWidth)
        .background {
            GeometryReader { proxy in
                ZStack {
                    AppVisualTokens.rootDetailFrameOpaqueFill
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
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppVisualTokens.rootDetailFrameBorder)
                .frame(width: 1)
        }
        .shadow(color: AppVisualTokens.rootDetailFrameShadow, radius: 16, x: 0, y: 2)
        .ignoresSafeArea(edges: [.top, .bottom, .trailing])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: collapsedCommandBarLeadingInset)
    }

    private var collapsedCommandBarLeadingInset: CGFloat {
        sidebarWidth <= 1 ? RootShellMetrics.collapsedCommandBarLeadingInset : 0
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

    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let base = sidebarDragBaseWidth ?? sidebarWidth
                        sidebarDragBaseWidth = base
                        let next = clampedSidebarWidth(base + value.translation.width)
                        sidebarWidth = next
                        lastExpandedSidebarWidth = next
                    }
                    .onEnded { _ in
                        sidebarDragBaseWidth = nil
                    }
            )
    }

    private func toggleSidebarCollapse() {
        if sidebarWidth <= 1 {
            let restored = clampedSidebarWidth(max(lastExpandedSidebarWidth, RootShellMetrics.sidebarMinWidth))
            if reduceMotion {
                sidebarWidth = restored
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    sidebarWidth = restored
                }
            }
        } else {
            lastExpandedSidebarWidth = clampedSidebarWidth(sidebarWidth)
            if reduceMotion {
                sidebarWidth = 0
            } else {
                withAnimation(.easeInOut(duration: 0.22)) {
                    sidebarWidth = 0
                }
            }
        }
    }

    private func clampedSidebarWidth(_ proposed: CGFloat) -> CGFloat {
        max(RootShellMetrics.sidebarMinWidth, min(RootShellMetrics.sidebarMaxWidth, proposed))
    }
}

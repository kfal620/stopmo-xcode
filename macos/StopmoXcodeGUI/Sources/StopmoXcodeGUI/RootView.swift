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
    @State private var sidebarWidth: CGFloat = 260
    @State private var lastExpandedSidebarWidth: CGFloat = 260
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
            RootShellBackdropMaterial()
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
        .overlay(alignment: .bottomLeading) {
            RootStatusBarView()
                .padding(.leading, 12)
                .padding(.bottom, 12)
        }
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
                AppVisualTokens.rootDetailFrameOpaqueFill
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.045),
                        Color.clear,
                    ],
                    center: .topLeading,
                    startRadius: 32,
                    endRadius: 560
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
        .overlay {
            DetailShellBorderShape(cornerRadius: AppVisualTokens.rootShellCornerRadius)
                .stroke(AppVisualTokens.rootDetailFrameBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppVisualTokens.rootShellCornerRadius, style: .continuous))
        .shadow(color: AppVisualTokens.rootDetailFrameShadow, radius: 14, x: 0, y: 5)
        .ignoresSafeArea(edges: [.top, .bottom, .trailing])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

private struct RootShellBackdropMaterial: View {
    var body: some View {
        ZStack {
            RootBackdropVisualEffect()
            Rectangle()
                .fill(AppVisualTokens.rootSidebarTintOverlay)
        }
        .ignoresSafeArea()
    }
}

private struct RootBackdropVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

private struct DetailShellBorderShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) * 0.5))
        var path = Path()

        // Draw only top/right/bottom border so the sidebar seam stays frameless.
        path.move(to: CGPoint(x: radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))

        return path
    }
}

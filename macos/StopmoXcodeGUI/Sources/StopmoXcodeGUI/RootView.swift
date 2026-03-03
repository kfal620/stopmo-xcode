import SwiftUI
import AppKit

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
    @State private var sidebarWidth: CGFloat = 260
    @State private var lastExpandedSidebarWidth: CGFloat = 260
    @State private var sidebarDragBaseWidth: CGFloat?
    @State private var isSidebarToggleHovered = false

    private let sidebarMinWidth: CGFloat = 220
    private let sidebarMaxWidth: CGFloat = 330
    private let detailMinWidth: CGFloat = 780
    private let sidebarHeaderBaseClearance: CGFloat = 34
    private let sidebarToggleBaseLeading: CGFloat = 90
    private let sidebarToggleBaseTop: CGFloat = 3   /// vertical padding for sidebar button
    private let titlebarControlsOffset = CGSize(width: 8, height: 8) /// hor + vert offset for traffic lights and sidebar button all together

    var body: some View {
        HStack(spacing: 0) {
            RootSidebarView(topContentInset: sidebarHeaderBaseClearance + titlebarControlsOffset.height)
                .frame(width: sidebarWidth)
                .opacity(sidebarWidth > 1 ? 1 : 0)
                .allowsHitTesting(sidebarWidth > 1)
                .clipped()

            if sidebarWidth > 1 {
                sidebarResizeHandle
            }

            detailShell
                .frame(minWidth: detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            collapseSidebarButton
                .padding(.leading, sidebarToggleBaseLeading + titlebarControlsOffset.width)
                .padding(.top, sidebarToggleBaseTop + titlebarControlsOffset.height)
                .ignoresSafeArea(edges: .top)
                .zIndex(220)
        }
        .background {
            RootWindowChromeConfigurator(titlebarControlsOffset: titlebarControlsOffset)
        }
    }
// MARK: Sidebar Button
    private var collapseSidebarButton: some View {
        Image(systemName: "sidebar.leading")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppVisualTokens.textSecondary)
            .frame(width: 28, height: 28, alignment: .center)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isSidebarToggleHovered ? 0.13 : 0))
            }
///            .overlay {
///                RoundedRectangle(cornerRadius: 10, style: .continuous)
///                    .stroke(Color.white.opacity(isSidebarToggleHovered ? 0.08 : 0), lineWidth: 0.8)
///            }
            .onTapGesture {
                toggleSidebarCollapse()
            }
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0)) {
                    isSidebarToggleHovered = hovering
                }
           }
            .accessibilityElement()
            .accessibilityLabel(sidebarWidth <= 1 ? "Expand sidebar" : "Collapse sidebar")
            .accessibilityAddTraits(.isButton)
            .help(sidebarWidth <= 1 ? "Expand sidebar" : "Collapse sidebar")
            .padding(.horizontal, 2)
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
            let restored = clampedSidebarWidth(max(lastExpandedSidebarWidth, sidebarMinWidth))
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
        max(sidebarMinWidth, min(sidebarMaxWidth, proposed))
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

private struct RootWindowChromeConfigurator: NSViewRepresentable {
    let titlebarControlsOffset: CGSize

    final class Coordinator: NSObject {
        weak var observedWindow: NSWindow?
        var onFrameChange: (() -> Void)?

        func observe(window: NSWindow, onFrameChange: @escaping () -> Void) {
            guard observedWindow !== window else { return }
            detachObservers()
            observedWindow = window
            self.onFrameChange = onFrameChange

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowDidResize),
                name: NSWindow.didResizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowDidEndLiveResize),
                name: NSWindow.didEndLiveResizeNotification,
                object: window
            )
        }

        @objc private func handleWindowDidResize(_ notification: Notification) {
            onFrameChange?()
        }

        @objc private func handleWindowDidEndLiveResize(_ notification: Notification) {
            onFrameChange?()
            // Reapply on next runloop tick so AppKit post-resize layout cannot override the custom position.
            perform(#selector(handleDeferredFrameChange), with: nil, afterDelay: 0)
        }

        @objc private func handleDeferredFrameChange() {
            onFrameChange?()
        }

        func detachObservers() {
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didResizeNotification,
                    object: observedWindow
                )
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didEndLiveResizeNotification,
                    object: observedWindow
                )
            }
            onFrameChange = nil
            observedWindow = nil
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detachObservers()
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }

        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        coordinator.observe(window: window) { [weak window] in
            guard let window else { return }
            updateTrafficLightPositions(in: window)
        }
        updateTrafficLightPositions(in: window)
    }

    private func updateTrafficLightPositions(in window: NSWindow) {
        guard
            let close = window.standardWindowButton(.closeButton),
            let buttonContainer = close.superview,
            let titlebarContainer = buttonContainer.superview
        else {
            return
        }

        let baseLeadingInset: CGFloat = 14
        let baseTopInset: CGFloat = 6
        let x = baseLeadingInset + titlebarControlsOffset.width
        let y = titlebarContainer.bounds.height - buttonContainer.frame.height - (baseTopInset + titlebarControlsOffset.height)

        buttonContainer.setFrameOrigin(
            NSPoint(
                x: x,
                y: y
            )
        )
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

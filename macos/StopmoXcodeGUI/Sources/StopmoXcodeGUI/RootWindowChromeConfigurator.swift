import SwiftUI
import AppKit

/// Projects traffic-light button origins from original system frames plus an offset.
struct TrafficLightFrameProjector {
    struct OriginalFrames: Equatable {
        let close: CGRect
        let miniaturize: CGRect
        let zoom: CGRect
    }

    struct ShiftedOrigins: Equatable {
        let close: CGPoint
        let miniaturize: CGPoint
        let zoom: CGPoint
    }

    static func shiftedOrigins(
        from originals: OriginalFrames,
        offset: CGSize
    ) -> ShiftedOrigins {
        ShiftedOrigins(
            close: CGPoint(
                x: originals.close.origin.x + offset.width,
                y: originals.close.origin.y - offset.height
            ),
            miniaturize: CGPoint(
                x: originals.miniaturize.origin.x + offset.width,
                y: originals.miniaturize.origin.y - offset.height
            ),
            zoom: CGPoint(
                x: originals.zoom.origin.x + offset.width,
                y: originals.zoom.origin.y - offset.height
            )
        )
    }
}

/// AppKit interop shim for custom titlebar chrome behavior in the root shell.
///
/// This is a controlled workaround: AppKit may relayout traffic-light controls during
/// resize/live-resize. We capture original system button frames once per window and always
/// apply offsets relative to those originals (never relative to current frames) to prevent
/// drift and post-resize snap-back.
struct RootWindowChromeConfigurator: NSViewRepresentable {
    let titlebarControlsOffset: CGSize

    @MainActor
    final class Coordinator: NSObject {
        weak var observedWindow: NSWindow?
        weak var observedCloseButton: NSButton?
        weak var observedMiniaturizeButton: NSButton?
        weak var observedZoomButton: NSButton?
        weak var observedButtonContainer: NSView?
        weak var observedTitlebarContainer: NSView?

        var titlebarControlsOffset: CGSize = .zero

        var closeButtonFrameObservation: NSKeyValueObservation?
        var miniaturizeButtonFrameObservation: NSKeyValueObservation?
        var zoomButtonFrameObservation: NSKeyValueObservation?

        var originalsWindowID: ObjectIdentifier?
        var originalButtonFrames: TrafficLightFrameProjector.OriginalFrames?
        var isApplyingShiftedFrames = false

        func bindWindow(_ window: NSWindow, offset: CGSize) {
            titlebarControlsOffset = offset

            if observedWindow !== window {
                unbind()
                observedWindow = window
                bindWindowObservers(for: window)
            }

            synchronizeTrafficLights(in: window)
        }

        private func bindWindowObservers(for window: NSWindow) {
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
            guard let window = observedWindow else { return }
            synchronizeTrafficLights(in: window)
        }

        @objc private func handleWindowDidEndLiveResize(_ notification: Notification) {
            guard let window = observedWindow else { return }
            synchronizeTrafficLights(in: window)

            // AppKit can relayout controls after live-resize completes; rebind/reapply on later ticks.
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0)
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0.03)
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0.08)
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0.16)
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0.3)
        }

        @objc private func handleDeferredApply() {
            guard let window = observedWindow else { return }
            synchronizeTrafficLights(in: window)
        }

        private func synchronizeTrafficLights(in window: NSWindow) {
            bindTitlebarControls(in: window)
            captureOriginalFramesIfNeeded(for: window)
            applyShiftedFrames()
        }

        private func bindTitlebarControls(in window: NSWindow) {
            guard
                let close = window.standardWindowButton(.closeButton),
                let miniaturize = window.standardWindowButton(.miniaturizeButton),
                let zoom = window.standardWindowButton(.zoomButton),
                let buttonContainer = close.superview,
                let titlebarContainer = buttonContainer.superview
            else {
                return
            }

            if observedCloseButton !== close || observedMiniaturizeButton !== miniaturize || observedZoomButton !== zoom {
                observedCloseButton = close
                observedMiniaturizeButton = miniaturize
                observedZoomButton = zoom
                bindButtonFrameObservers()
            }

            observedButtonContainer = buttonContainer
            observedTitlebarContainer = titlebarContainer
        }

        private func bindButtonFrameObservers() {
            closeButtonFrameObservation?.invalidate()
            miniaturizeButtonFrameObservation?.invalidate()
            zoomButtonFrameObservation?.invalidate()

            closeButtonFrameObservation = observedCloseButton?.observe(\.frame, options: [.new]) { [weak self] _, _ in
                self?.perform(#selector(Coordinator.handleButtonFrameMutation), with: nil, afterDelay: 0)
            }
            miniaturizeButtonFrameObservation = observedMiniaturizeButton?.observe(\.frame, options: [.new]) { [weak self] _, _ in
                self?.perform(#selector(Coordinator.handleButtonFrameMutation), with: nil, afterDelay: 0)
            }
            zoomButtonFrameObservation = observedZoomButton?.observe(\.frame, options: [.new]) { [weak self] _, _ in
                self?.perform(#selector(Coordinator.handleButtonFrameMutation), with: nil, afterDelay: 0)
            }
        }

        @objc private func handleButtonFrameMutation() {
            if isApplyingShiftedFrames {
                return
            }
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0)
        }

        private func captureOriginalFramesIfNeeded(for window: NSWindow) {
            let key = ObjectIdentifier(window)
            if originalsWindowID != key {
                originalsWindowID = key
                originalButtonFrames = nil
            }

            if originalButtonFrames == nil,
               let close = observedCloseButton,
               let miniaturize = observedMiniaturizeButton,
               let zoom = observedZoomButton {
                originalButtonFrames = TrafficLightFrameProjector.OriginalFrames(
                    close: close.frame,
                    miniaturize: miniaturize.frame,
                    zoom: zoom.frame
                )
            }
        }

        private func applyShiftedFrames() {
            guard
                let originals = originalButtonFrames,
                let close = observedCloseButton,
                let miniaturize = observedMiniaturizeButton,
                let zoom = observedZoomButton
            else {
                return
            }

            let projected = TrafficLightFrameProjector.shiftedOrigins(
                from: originals,
                offset: titlebarControlsOffset
            )

            isApplyingShiftedFrames = true
            defer { isApplyingShiftedFrames = false }

            if close.frame.origin != projected.close {
                close.setFrameOrigin(projected.close)
            }
            if miniaturize.frame.origin != projected.miniaturize {
                miniaturize.setFrameOrigin(projected.miniaturize)
            }
            if zoom.frame.origin != projected.zoom {
                zoom.setFrameOrigin(projected.zoom)
            }

            refreshTrafficLightTrackingAreas()
        }

        /// AppKit sometimes keeps stale rollover tracking areas after manual frame changes.
        /// Refreshing on the buttons + enclosing titlebar views keeps hover hotspots aligned.
        private func refreshTrafficLightTrackingAreas() {
            let views: [NSView?] = [
                observedCloseButton,
                observedMiniaturizeButton,
                observedZoomButton,
                observedButtonContainer,
                observedTitlebarContainer,
            ]

            for view in views {
                guard let view else { continue }
                for trackingArea in view.trackingAreas {
                    view.removeTrackingArea(trackingArea)
                }
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
                view.updateTrackingAreas()
                view.resetCursorRects()
                view.window?.invalidateCursorRects(for: view)
                view.needsDisplay = true
            }
        }

        func unbind() {
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

            closeButtonFrameObservation?.invalidate()
            miniaturizeButtonFrameObservation?.invalidate()
            zoomButtonFrameObservation?.invalidate()
            closeButtonFrameObservation = nil
            miniaturizeButtonFrameObservation = nil
            zoomButtonFrameObservation = nil

            observedCloseButton = nil
            observedMiniaturizeButton = nil
            observedZoomButton = nil
            observedButtonContainer = nil
            observedTitlebarContainer = nil

            originalsWindowID = nil
            originalButtonFrames = nil
            isApplyingShiftedFrames = false
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
        coordinator.unbind()
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
        coordinator.bindWindow(window, offset: titlebarControlsOffset)
    }
}

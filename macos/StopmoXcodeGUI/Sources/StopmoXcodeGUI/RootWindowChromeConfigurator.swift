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
/// resize/live-resize. We capture the original system button frames and the original
/// traffic-light container frame once per window, then always reapply the offset relative
/// to that original container frame to prevent drift and hover-hit mismatches.
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

        var buttonContainerObservation: NSKeyValueObservation?

        var originalsWindowID: ObjectIdentifier?
        var originalButtonFrames: TrafficLightFrameProjector.OriginalFrames?
        var originalButtonContainerFrame: CGRect?

        func bindWindow(_ window: NSWindow, offset: CGSize) {
            titlebarControlsOffset = offset

            if observedWindow !== window {
                unbind()
                observedWindow = window
                bindWindowObservers(for: window)
            }

            bindTitlebarControls(in: window)
            captureOriginalFramesIfNeeded(for: window)
            applyShiftedFrames()
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
            bindTitlebarControls(in: window)
            captureOriginalFramesIfNeeded(for: window)
            applyShiftedFrames()
        }

        @objc private func handleWindowDidEndLiveResize(_ notification: Notification) {
            guard let window = observedWindow else { return }
            bindTitlebarControls(in: window)
            captureOriginalFramesIfNeeded(for: window)
            applyShiftedFrames()

            // AppKit can relayout controls at the end of live resize; reapply on next ticks.
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0)
            perform(#selector(handleDeferredApply), with: nil, afterDelay: 0.05)
        }

        @objc private func handleDeferredApply() {
            applyShiftedFrames()
            refreshTrafficLightTrackingAreas()
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

            var hierarchyChanged = false

            if observedCloseButton !== close || observedMiniaturizeButton !== miniaturize || observedZoomButton !== zoom {
                observedCloseButton = close
                observedMiniaturizeButton = miniaturize
                observedZoomButton = zoom
                hierarchyChanged = true
            }

            if observedButtonContainer !== buttonContainer {
                buttonContainerObservation?.invalidate()
                observedButtonContainer = buttonContainer
                buttonContainerObservation = buttonContainer.observe(\.frame, options: [.new]) { [weak self] _, _ in
                    self?.perform(#selector(Coordinator.handleDeferredApply), with: nil, afterDelay: 0)
                }
                hierarchyChanged = true
            }

            if observedTitlebarContainer !== titlebarContainer {
                observedTitlebarContainer = titlebarContainer
                hierarchyChanged = true
            }

            if hierarchyChanged {
                originalsWindowID = nil
                originalButtonFrames = nil
                originalButtonContainerFrame = nil
            }
        }

        private func captureOriginalFramesIfNeeded(for window: NSWindow) {
            let key = ObjectIdentifier(window)
            if originalsWindowID != key {
                originalsWindowID = key
                originalButtonFrames = nil
                originalButtonContainerFrame = nil
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

            if originalButtonContainerFrame == nil,
               let buttonContainer = observedButtonContainer {
                originalButtonContainerFrame = buttonContainer.frame
            }
        }

        private func applyShiftedFrames() {
            guard
                let buttonContainer = observedButtonContainer,
                let originalButtonContainerFrame
            else {
                return
            }

            let nextOrigin = CGPoint(
                x: originalButtonContainerFrame.origin.x + titlebarControlsOffset.width,
                y: originalButtonContainerFrame.origin.y - titlebarControlsOffset.height
            )
            if buttonContainer.frame.origin != nextOrigin {
                buttonContainer.setFrameOrigin(nextOrigin)
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

            buttonContainerObservation?.invalidate()
            buttonContainerObservation = nil

            observedCloseButton = nil
            observedMiniaturizeButton = nil
            observedZoomButton = nil
            observedButtonContainer = nil
            observedTitlebarContainer = nil

            originalsWindowID = nil
            originalButtonFrames = nil
            originalButtonContainerFrame = nil
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

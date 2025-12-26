//
//  FloatingControlsWindow.swift
//  SaneVideo
//

import AppKit
import SwiftUI

class FloatingControlsWindow: NSPanel {
    private var hideTimer: Timer?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        let initialFrame = NSRect(x: 0, y: 0, width: 600, height: 100)

        super.init(
            contentRect: initialFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false

        setupWindow()
        centerOnScreen()
        setupMouseTracking()
    }

    private func setupWindow() {
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // CRITICAL FIX: Prevent controls from appearing in screen share picker
        if #available(macOS 15.0, *) {
            self.sharingType = .none
        } else {
            self.sharingType = .none
        }

        // Floating controls use .medium size for better visibility
        // when user is screen sharing and app is minimized
        let controlsView = SharedRecordingControls(
            showDevicePickers: false,
            showGalleryTarget: false,
            showTimer: true,
            useGlassBackground: true,
            buttonSize: .medium  // Uses unified size (52pt buttons, 73pt record)
        )
        contentView = NSHostingView(rootView: controlsView
            .environment(ServiceContainer.shared.appState)
        )
    }

    private func centerOnScreen() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = frame
            let xPos = screenFrame.midX - windowFrame.width / 2
            let yPos = screenFrame.maxY - windowFrame.height - 20
            setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
    }

    private func setupMouseTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView?.addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        showControls()
        resetHideTimer()
    }

    private func showControls() {
        alphaValue = 1.0
    }

    private func hideControls() {
        alphaValue = 0.3
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        // CRITICAL FIX: Create timer on main run loop explicitly
        // This ensures timer fires reliably on main thread
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            // Already on main thread from Timer on main RunLoop
            self?.hideControls()
        }
        // Ensure timer is added to common run loop modes (for scrolling, etc.)
        if let timer = hideTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    override func close() {
        // CRITICAL FIX: Prevent _NSWindowTransformAnimation crash
        // Same fix as PiPCameraWindow - properly sequence the close

        // 1. Invalidate timer to stop any pending callbacks
        hideTimer?.invalidate()
        hideTimer = nil

        // 2. Disable animations and cleanup synchronously
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Hide window immediately
        alphaValue = 0

        // 3. Remove subviews
        contentView?.subviews.forEach { subview in
            subview.isHidden = true
            subview.removeFromSuperview()
        }

        CATransaction.commit()

        // 4. Order out
        orderOut(nil)

        // 5. Delay then close (call super synchronously after delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Use performSelector to call super.close() without capturing self in closure
            self.performSuperClose()
        }
    }

    // Helper to call super.close() - avoids closure capture issue
    private func performSuperClose() {
        super.close()
    }

    deinit {
        // Safety net: rely on close() being called for cleanup
    }

}

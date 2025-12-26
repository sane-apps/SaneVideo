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

        // Set content view to SwiftUI
        let controlsView = SharedRecordingControls(
            showDevicePickers: false,
            showGalleryTarget: false,
            showTimer: true,
            useGlassBackground: true,
            buttonSize: .small
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
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideControls()
            }
        }
    }
    override func close() {
        // CRITICAL FIX: Invalidate timer before closing
        hideTimer?.invalidate()
        hideTimer = nil

        // CRITICAL FIX: Remove content view's subviews before closing
        // This ensures SwiftUI hosting view is properly dismantled
        contentView?.subviews.forEach { $0.removeFromSuperview() }

        super.close()
    }

    deinit {
        // Safety net: rely on close() being called for cleanup
    }

}

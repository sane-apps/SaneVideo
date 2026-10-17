import AppKit
import SwiftUI

class FloatingControlsWindow: NSPanel {
    static let preferredPanelSize = NSSize(
        width: ceil(
            SharedRecordingControls.minimumBarWidth(
                buttonSize: .medium,
                includePauseControl: true,
                showTimer: true,
                showGalleryTarget: false
            ) + Theme.Dimensions.paddingXL
        ),
        height: 112
    )

    private var hideTimer: Timer?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        let initialFrame = NSRect(origin: .zero, size: Self.preferredPanelSize)

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
        minSize = Self.preferredPanelSize
        setContentSize(Self.preferredPanelSize)

        if #available(macOS 15.0, *) {
            self.sharingType = .none
        } else {
            self.sharingType = .none
        }

        // Medium buttons stay easy to see while the user screen shares with the app minimized.
        let controlsView = SharedRecordingControls(
            showDevicePickers: false,
            showGalleryTarget: false,
            showTimer: true,
            useGlassBackground: true,
            buttonSize: .medium  // 52pt buttons, 73pt record button
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
            // Already on main thread from Timer on main RunLoop
            Task { @MainActor in
                self?.hideControls()
            }
        }
        // Common modes keep the timer firing during scrolling and menu tracking.
        if let timer = hideTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    override func close() {
        // Close synchronously with animations off, as in PiPCameraWindow, to avoid the _NSWindowTransformAnimation crash.

        hideTimer?.invalidate()
        hideTimer = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        alphaValue = 0

        contentView?.subviews.forEach { subview in
            subview.isHidden = true
            subview.removeFromSuperview()
        }

        CATransaction.commit()

        orderOut(nil)

        // Do not use asyncAfter here; it races with isReleasedWhenClosed.
        super.close()
    }

    deinit {
        // Cleanup happens in close().
    }

}

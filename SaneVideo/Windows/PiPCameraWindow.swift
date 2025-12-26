//
//  PiPCameraWindow.swift
//  SaneVideo
//
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

class PiPCameraWindow: NSPanel {
    private var previewView: NSView?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cancellables = Set<AnyCancellable>()

    // CRITICAL FIX: Embed controls directly in PiPCameraWindow to prevent detachment.
    private var controlsHostingView: NSHostingView<AnyView>?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // CRITICAL FIX: Handle screen configuration changes
    @objc private func screenConfigurationChanged() {
        // Re-snap to corner if window is visible and valid
        guard isVisible,
              windowNumber > 0,
              !isReleasedWhenClosed else { return }

        // Re-snap to last known corner (default to bottomRight)
        snapToCorner(.bottomRight)
        AppLogger.window.info("PiP window re-positioned after screen configuration change")
    }

    deinit {
        // NOTE: Do NOT call AppLogger here - it creates Tasks which is unsafe in deinit
        // CRITICAL FIX: Remove observer on deallocation
        NotificationCenter.default.removeObserver(self)
        // CRITICAL FIX: Cleanup should happen in close(), but as safety net:
        // Note: Can't access MainActor properties in nonisolated deinit
        // Rely on close() being called properly
    }

    convenience init() {
        let screen = NSScreen.main?.frame ?? .zero
        let initialFrame = NSRect(
            x: screen.maxX - 400, // defaults
            y: 40,
            width: 360, // Increased from 320 to fit controls + resize handle
            height: 240
        )

        // Call designated initializer on self (inherited)
        self.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Properties are already initialized by defaults

        isReleasedWhenClosed = false
        title = "SaneVideo PiP"

        // CRITICAL FIX: Observe screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        setupWindow()
        // Initial layout
        embedControls()
        setupPreview()
        setupObservers()
    }

    private func embedControls() {
        guard let contentView = self.contentView else { return }

        // Remove existing if any
        controlsHostingView?.removeFromSuperview()

        // CRITICAL: We pass the AppState environment so controls work
        let controlsView = SharedRecordingControls(
            showDevicePickers: false,
            showGalleryTarget: false,
            showTimer: false,
            useGlassBackground: true,
            buttonSize: .small,
            recordButtonSize: 44
        )
        .environment(ServiceContainer.shared.appState)

        let hosting = NSHostingView(rootView: AnyView(controlsView))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Allow clicks on buttons, but pass background clicks to window for moving
        // NSHostingView background is clear by default in this context?
        // We set layer check just in case.

        contentView.addSubview(hosting)
        controlsHostingView = hosting

        NSLayoutConstraint.activate([
            // Position at bottom center
            hosting.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hosting.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            // Ensure width fits content
            hosting.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            hosting.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            // Ensure it doesn't overlap resize handle (bottom right)
            hosting.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40)
        ])
    }

    // Keeping this method signature to minimize diff/breakage
    func updateControlsVisibility(isVisible: Bool) {
        controlsHostingView?.isHidden = !isVisible
    }

    private func setupWindow() {
        level = .floating // Reverted to .floating to ensure visibility in ScreenCaptureKit
        hidesOnDeactivate = false // CRITICAL: Keeps window visible when switching apps
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // CRITICAL FIX: Disable built-in background moving as it can intercept button clicks
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Fix: Enable PiP window in screen capture.
        if #available(macOS 15.0, *) {
            self.sharingType = .readOnly
        } else {
            self.sharingType = .readWrite
        }

        // Ensure no title bar or border
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        guard let contentView else { return }

        // Add visual effect view for nice background
        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.autoresizingMask = [.width, .height]

        contentView.addSubview(visualEffect)

        // CRITICAL FIX: Add resize handle to contentView directly, NOT visualEffect
        // This ensures it can be layered on top of the video preview
        let resizeHandle = ResizeHandleView(window: self)
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resizeHandle) // Add to contentView

        NSLayoutConstraint.activate([
            resizeHandle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            resizeHandle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            resizeHandle.widthAnchor.constraint(equalToConstant: 40), // Larger, easier to grab
            resizeHandle.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    // MARK: - Internal Helpers
    // Custom view to handle manual window resizing (bottom-right corner)
    private class ResizeHandleView: NSView {
        weak var windowToResize: NSWindow?
        private let imageView = NSImageView()

        init(window: NSWindow) {
            windowToResize = window
            super.init(frame: .zero)
            setupView()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private func setupView() {
            // Icon
            imageView.image = NSImage(
                systemSymbolName: "arrow.up.left.and.arrow.down.right",
                accessibilityDescription: "Resize"
            )
            imageView.contentTintColor = .secondaryLabelColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)

            // Centered icon, but view itself is the larger hit area
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 20), // Slightly larger icon for visibility
                imageView.heightAnchor.constraint(equalToConstant: 20)
            ])

            // Add cursor tracking
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
        }

        override func cursorUpdate(with _: NSEvent) {
            NSCursor.resizeLeftRight.set() // Or specific diagonal cursor if available? NSCursor doesn't have diagonal public API easily?
            // Just let system handle it or stick to arrow.
        }

        override func mouseDown(with _: NSEvent) {
            // Required to capture mouseDragged
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window = windowToResize else { return }

            // 1. Calculate change in width
            // We drive resizing primarily by horizontal movement for stability
            let dX = event.deltaX
            var newWidth = window.frame.width + dX

            // 2. Enforce Aspect Ratio (3:2 = 1.5)
            // This prevents "free form" distortion requested by user
            let aspectRatio: CGFloat = 1.5

            // 3. Apply Min/Max Constraints
            let minWidth: CGFloat = 200
            let maxWidth: CGFloat = 800
            newWidth = max(minWidth, min(maxWidth, newWidth))

            let newHeight = newWidth / aspectRatio

            // 4. Calculate new origin (Anchor Top-Left)
            // macOS Coordinate system: Origin is Bottom-Left.
            // To keep Top-Left fixed while resizing Bottom-Right:
            // Top (MaxY) should stay constant.
            // NewOrigin.y = OldMaxY - NewHeight
            let currentMaxY = window.frame.maxY
            let newY = currentMaxY - newHeight

            let newFrame = NSRect(
                x: window.frame.origin.x, // Left stays fixed
                y: newY,
                width: newWidth,
                height: newHeight
            )

            window.setFrame(newFrame, display: true)
        }
    }

    private func setupObservers() {
        ServiceContainer.shared.cameraService.sessionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                self?.updatePreview(with: session)
            }
            .store(in: &cancellables)
    }

    func setupPreview() {
        updatePreview(with: ServiceContainer.shared.cameraService.session)
    }

    private func updatePreview(with session: AVCaptureSession?) {
        // CRITICAL: Must run on main thread for AVFoundation layer operations
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePreview(with: session)
            }
            return
        }

        // If we already have a layer for this session, do nothing
        if let currentLayer = previewLayer, currentLayer.session === session {
            return
        }

        // CRITICAL FIX: Remove existing layer with proper cleanup
        // Disconnect session BEFORE removing to prevent use-after-free
        previewLayer?.session = nil
        previewLayer?.removeFromSuperlayer()
        previewView?.removeFromSuperview()
        previewView = nil
        previewLayer = nil

        guard let session else {
            AppLogger.camera.info("PiP: No camera session available yet (session is nil)")
            return
        }

        AppLogger.camera.info("PiP: updatePreview called with session. isRunning: \(session.isRunning), inputs: \(session.inputs.count)")

        // Safety check for contentView
        guard let contentView = contentView else {
            AppLogger.camera.error("PiP: ContentView is nil!")
            return
        }

        let containerView = NSView(frame: contentView.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor

        let newLayer = AVCaptureVideoPreviewLayer(session: session)
        newLayer.frame = containerView.bounds
        newLayer.cornerRadius = 12
        newLayer.masksToBounds = true
        newLayer.videoGravity = .resizeAspectFill

        // Ensure layer is visible
        newLayer.isHidden = false
        newLayer.opacity = 1.0

        containerView.layer?.addSublayer(newLayer)
        containerView.autoresizingMask = [.width, .height]

        // Add to contentView
        contentView.addSubview(containerView)

        // Ensure container is on top of visual effect view
        if let visualEffect = contentView.subviews.first(where: { $0 is NSVisualEffectView }) {
            contentView.addSubview(containerView, positioned: .above, relativeTo: visualEffect)
        } else {
             contentView.addSubview(containerView)
        }

        // CRITICAL FIX: Ensure Resize Handle stays on top of video
        // Find the resizing handle and bring it to front
        if let resizeHandle = contentView.subviews.first(where: { $0 is ResizeHandleView }) {
            // Re-add to bring to front of subview array
            resizeHandle.removeFromSuperview()
            contentView.addSubview(resizeHandle)
        }

        // CRITICAL FIX: Ensure Controls stay on top of video
        if let controls = controlsHostingView {
            controls.removeFromSuperview()
            contentView.addSubview(controls) // Add last = Top
            // Activate constraints again? No, constraints remain valid if view is same?
            // Actually removing from superview breaks constraints usually if they reference superview.
            // We need to re-activate constraints if we remove/add.
            // Better strategy: Use `positioned: .above` when adding video layer?
            // Video layer should be strictly below controls.
            // Let's just re-embed controls logic or re-constrain.
            // Simplest: `embedControls()` calls `removeFromSuperview` and re-adds and re-constraints.
            // So we can just call `embedControls()` here again to be safe and ensure Z-order.
            embedControls()
        }

        previewView = containerView
        previewLayer = newLayer

        // CRITICAL FIX: Configure connection after layer is fully set up
        // Defer to next run loop to allow AVFoundation internal setup
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let connection = self.previewLayer?.connection,
                  self.previewLayer?.session === session else { return }

            // Configure connection properties
            // CRITICAL: Must disable automaticallyAdjustsVideoMirroring BEFORE setting isVideoMirrored
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
                AppLogger.camera.info("PiP: Configured video mirroring")
            }
        }
    }

    override func close() {
        // CRITICAL FIX: Cleanup preview layer and cancellables before closing
        // Disconnect session BEFORE removing layer to prevent use-after-free
        previewLayer?.session = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        previewView?.removeFromSuperview()
        previewView = nil

        // CRITICAL FIX: Explicitly remove controls hosting view to invalidate SwiftUI subscriptions
        controlsHostingView?.removeFromSuperview()
        controlsHostingView = nil

        cancellables.removeAll()

        super.close()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)

        // Update preview layer frame
        if let containerView = previewView,
           let layer = previewLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = containerView.bounds
            CATransaction.commit()
        }
    }

    func snapToCorner(_ corner: ScreenCorner) {
        // CRITICAL FIX: Validate screen exists and window is valid
        guard let screen = NSScreen.main,
              windowNumber > 0,
              !isReleasedWhenClosed else {
            AppLogger.window.warning("Cannot snap window: invalid screen or window state")
            return
        }

        let margin: CGFloat = 40
        let newOrigin = switch corner {
        case .bottomRight:
            NSPoint(
                x: screen.frame.maxX - frame.width - margin,
                y: margin
            )
        case .bottomLeft:
            NSPoint(x: margin, y: margin)
        case .topRight:
            NSPoint(
                x: screen.frame.maxX - frame.width - margin,
                y: screen.frame.maxY - frame.height - margin
            )
        case .topLeft:
            NSPoint(
                x: margin,
                y: screen.frame.maxY - frame.height - margin
            )
        }

        setFrameOrigin(newOrigin)
    }

    enum ScreenCorner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

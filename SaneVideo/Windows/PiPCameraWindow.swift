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
        // Default size: 320x240 video + 60pt for controls = 320x300
        // Position in bottom-right corner with padding
        let pipWidth: CGFloat = 320
        let pipHeight: CGFloat = 280  // 16:9 video + controls
        let initialFrame = NSRect(
            x: screen.maxX - pipWidth - 20,
            y: 40,
            width: pipWidth,
            height: pipHeight
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

        // PiP uses .small button size (40pt) for compact display
        // Record button auto-scales to 56pt (40 * 1.4)
        let controlsView = SharedRecordingControls(
            showDevicePickers: false,
            showGalleryTarget: false,
            showTimer: false,
            useGlassBackground: true,
            buttonSize: .small  // Uses unified size system (40pt buttons, 56pt record)
        )
        .environment(ServiceContainer.shared.appState)

        let hosting = NSHostingView(rootView: AnyView(controlsView))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(hosting)
        controlsHostingView = hosting

        // Use Theme.Dimensions for consistent spacing
        let bottomPadding = Theme.Dimensions.paddingLG  // 16pt
        let sidePadding = Theme.Dimensions.paddingXL    // 20pt (for resize handle clearance)

        NSLayoutConstraint.activate([
            // Position at bottom center with proper margins
            hosting.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hosting.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -bottomPadding),
            // Ensure width fits content
            hosting.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            hosting.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            // Keep clear of resize handle (bottom right)
            hosting.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -sidePadding * 2)
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
        // Enable dragging by window background (video area)
        // Buttons have their own hit testing so they still work
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // CRITICAL FIX: Prevent PiP from appearing in screen share picker
        // We use .none so the window cannot be captured at all
        // The camera is composited separately by VideoWriter
        if #available(macOS 15.0, *) {
            self.sharingType = .none
        } else {
            // Pre-macOS 15, use level to avoid capture
            self.sharingType = .none
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
        contentView.addSubview(resizeHandle)

        // Use consistent spacing from Theme
        let handlePadding = Theme.Dimensions.paddingXS  // 4pt
        let handleSize: CGFloat = 36  // Comfortable touch target

        NSLayoutConstraint.activate([
            resizeHandle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -handlePadding),
            resizeHandle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -handlePadding),
            resizeHandle.widthAnchor.constraint(equalToConstant: handleSize),
            resizeHandle.heightAnchor.constraint(equalToConstant: handleSize)
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

        // CRITICAL FIX: Use z-ordering without removing/re-adding views
        // Removing views breaks constraints and causes use-after-free crashes
        // Instead, use sortSubviews to reorder the z-index
        contentView.sortSubviews({ (view1, view2, _) -> ComparisonResult in
            // Order: visualEffect < containerView < resizeHandle < controls
            let order: [String: Int] = [
                "NSVisualEffectView": 0,
                "NSView": 1,  // containerView for video
                "ResizeHandleView": 2,
                "NSHostingView": 3  // controls on top
            ]
            let type1 = String(describing: type(of: view1))
            let type2 = String(describing: type(of: view2))
            let priority1 = order.first(where: { type1.contains($0.key) })?.value ?? 1
            let priority2 = order.first(where: { type2.contains($0.key) })?.value ?? 1
            if priority1 < priority2 { return .orderedAscending }
            if priority1 > priority2 { return .orderedDescending }
            return .orderedSame
        }, context: nil)

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
        // CRITICAL FIX: Prevent _NSWindowTransformAnimation crash
        // The crash occurs because NSWindow animations are still running when dealloc happens.
        // Solution: Disable animations, cleanup synchronously, then close.

        // 1. Cancel all Combine subscriptions to stop async callbacks
        cancellables.removeAll()

        // 2. Disconnect camera session FIRST (prevents AVFoundation callbacks)
        previewLayer?.session = nil

        // 3. Disable animations and cleanup synchronously
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Hide window immediately
        alphaValue = 0

        // 4. Remove layers and views
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        controlsHostingView?.isHidden = true
        controlsHostingView?.removeFromSuperview()
        controlsHostingView = nil

        previewView?.removeFromSuperview()
        previewView = nil

        CATransaction.commit()

        // 5. Order out (removes from screen, stops window server animations)
        orderOut(nil)

        // 6. Small delay to let window server finish cleanup, then close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.performSuperClose()
        }
    }

    // Helper to call super.close() - avoids closure capture issue with super
    private func performSuperClose() {
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

//  PiPCameraWindow.swift
//  SaneVideo
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

class PiPCameraWindow: NSPanel {
    private var previewView: NSView?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cancellables = Set<AnyCancellable>()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Child window for controls (Excluded from recording)
    var controlsWindow: PiPControlsWindow?

    deinit {
        print("⚰️ PiPCameraWindow deinit")
    }

    convenience init() {
        let screen = NSScreen.main?.frame ?? .zero
        let initialFrame = NSRect(
            x: screen.maxX - 360, // defaults
            y: 40,
            width: 320,
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
        
        setupWindow()
        setupPreview()
        setupObservers()
        
        // Setup separate controls window
        setupControlsWindow()
    }

    private func setupWindow() {
        level = .statusBar // CRITICAL FIX: Upgrade from .floating to ensure "Always on Top" even over fullscreen apps
        hidesOnDeactivate = false // CRITICAL: Keeps window visible when switching apps
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Fix: Enable PiP window in screen capture. 
        // Previously set to .none to prevent recursive capture, but this hides the camera from the user's recording.
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

        // Add functional resize handle
        let resizeHandle = ResizeHandleView(window: self)
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(resizeHandle)

        NSLayoutConstraint.activate([
            resizeHandle.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -4),
            resizeHandle.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -4),
            resizeHandle.widthAnchor.constraint(equalToConstant: 24), // Larger hit area
            resizeHandle.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    private func setupControlsWindow() {
        // Create controls window with synchronized frame
        let controls = PiPControlsWindow(frame: frame)
        self.addChildWindow(controls, ordered: .above)
        self.controlsWindow = controls
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
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16)
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

            let dX = event.deltaX
            let dY = event.deltaY

            var newFrame = window.frame

            // Standard macOS geometry:
            // Dragging Right (dX > 0) -> Width increases
            // Dragging Down (dY < 0) -> Height increases, Y decreases

            newFrame.size.width += dX
            newFrame.size.height -= dY // dY is negative when moving down
            newFrame.origin.y += dY // Move origin down

            // Min Size Limits
            let minWidth: CGFloat = 160
            let minHeight: CGFloat = 120

            if newFrame.size.width < minWidth {
                newFrame.size.width = minWidth
            }

            if newFrame.size.height < minHeight {
                let diff = minHeight - newFrame.size.height
                newFrame.size.height = minHeight
                newFrame.origin.y -= diff // Correct back the origin shift
            }

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

        // Remove existing
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
        controlsWindow?.close()
        controlsWindow = nil
        super.close()
    }

    override func orderOut(_ sender: Any?) {
        controlsWindow?.orderOut(sender)
        super.orderOut(sender)
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
        
        // Sync Child Window Frame
        if let controls = controlsWindow {
            controls.setFrame(frameRect, display: flag)
        }
    }

    func snapToCorner(_ corner: ScreenCorner) {
        guard let screen = NSScreen.main else { return }

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

// PiPControlsView is now defined in Views/Components/PiPControlsView.swift

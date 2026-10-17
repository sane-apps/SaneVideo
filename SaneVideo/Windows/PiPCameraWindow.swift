import AppKit
import AVFoundation
import Combine
import SwiftUI

class PiPCameraWindow: NSPanel {
    private var previewView: NSView?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cancellables = Set<AnyCancellable>()

    // Embed controls directly in PiPCameraWindow to prevent detachment.
    private var controlsHostingView: NSHostingView<AnyView>?

    // MARK: - Size Presets (user-friendly defaults based on industry research)
    enum PiPSize: Int, CaseIterable {
        case small = 0   // 200px - minimal, just your face
        case medium = 1  // 320px - balanced (default)
        case large = 2   // 480px - detailed view

        var width: CGFloat {
            switch self {
            case .small: return 200
            case .medium: return 320
            case .large: return 480
            }
        }

        // Height based on 3:2 aspect ratio
        var height: CGFloat { width / 1.5 }

        var next: PiPSize {
            let allCases = PiPSize.allCases
            let nextIndex = (rawValue + 1) % allCases.count
            return allCases[nextIndex]
        }

        static func fromWidth(_ width: CGFloat) -> PiPSize {
            switch width {
            case ..<260: return .small
            case 260..<400: return .medium
            default: return .large
            }
        }
    }

    private var currentButtonSize: IconCircleButton.Size = .small

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc private func screenConfigurationChanged() {
        guard isVisible,
              windowNumber > 0,
              !isReleasedWhenClosed else { return }

        snapToCorner(.bottomRight)
        AppLogger.window.info("PiP window re-positioned after screen configuration change")
    }

    deinit {
        // No AppLogger here: it creates Tasks, which is unsafe in deinit.
        NotificationCenter.default.removeObserver(self)
        // The nonisolated deinit cannot touch MainActor state, so cleanup happens in close().
    }

    convenience init() {
        let screen = NSScreen.main?.frame ?? .zero

        let savedSizeRaw = UserDefaults.standard.integer(forKey: "pipPreferredSize")
        let savedPreset = PiPSize(rawValue: savedSizeRaw) ?? .medium

        let pipWidth: CGFloat = savedPreset.width
        let pipHeight: CGFloat = savedPreset.height

        let initialFrame = NSRect(
            x: screen.maxX - pipWidth - 20,
            y: 40,
            width: pipWidth,
            height: pipHeight
        )

        self.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        title = "SaneVideo PiP"

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        setupWindow()
        embedControls()
        setupPreview()
        setupObservers()
    }

    private func embedControls() {
        guard let contentView = self.contentView else { return }

        controlsHostingView?.removeFromSuperview()

        currentButtonSize = IconCircleButton.Size.forPiPWidth(frame.width)

        // Wrap controls with countdown overlay so PiP users see the countdown too
        let controlsWithCountdown = PiPControlsWithCountdown(buttonSize: currentButtonSize)
            .environment(ServiceContainer.shared.appState)

        let hosting = NSHostingView(rootView: AnyView(controlsWithCountdown))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(hosting)
        controlsHostingView = hosting

        let bottomPadding: CGFloat = currentButtonSize == .mini ? 8 : Theme.Dimensions.paddingLG
        let sidePadding: CGFloat = currentButtonSize == .mini ? 12 : Theme.Dimensions.paddingXL
        let minWidth: CGFloat = currentButtonSize == .mini ? 120 : 180
        let minHeight: CGFloat = currentButtonSize == .mini ? 36 : 52

        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hosting.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -bottomPadding),
            hosting.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            hosting.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
            // Keep clear of resize handle (bottom right)
            hosting.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -sidePadding * 2)
        ])
    }

    /// Re-embed controls when size changes significantly (to update button sizes)
    private func updateControlsForCurrentSize() {
        let newSize = IconCircleButton.Size.forPiPWidth(frame.width)
        if newSize != currentButtonSize {
            embedControls()
        }
    }

    func cycleToNextSize() {
        let currentPreset = PiPSize.fromWidth(frame.width)
        let nextPreset = currentPreset.next
        resizeToPreset(nextPreset)
    }

    func resizeToPreset(_ preset: PiPSize) {
        let newWidth = preset.width
        let newHeight = preset.height

        // Keep top-left anchored (same as manual resize)
        let currentMaxY = frame.maxY
        let newY = currentMaxY - newHeight

        let newFrame = NSRect(
            x: frame.origin.x,
            y: newY,
            width: newWidth,
            height: newHeight
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }

        // Update controls once the 0.2 s animation finishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.updateControlsForCurrentSize()
        }

        UserDefaults.standard.set(preset.rawValue, forKey: "pipPreferredSize")
    }

    func applyLayout(_ layout: PresenterOverlayLayout) {
        guard let screen = NSScreen.main else { return }

        let targetFrame = frameForLayout(layout, on: screen)
        setFrame(targetFrame, display: true)
        updateControlsForCurrentSize()
    }

    func updateControlsVisibility(isVisible: Bool) {
        controlsHostingView?.isHidden = !isVisible
    }

    private func setupWindow() {
        level = .floating

        hidesOnDeactivate = false // Stay visible when the user switches apps
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Drag by the background; buttons keep their own hit testing.
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // sharingType .none hides PiP from the share picker and from capture; VideoWriter composites the camera separately.
        self.sharingType = .none

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        guard let contentView else { return }

        let glassView = LiquidGlassNSView(intensity: .premium, cornerRadius: PresenterOverlayLayout.cornerRadius)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(glassView)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: contentView.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Add the resize handle to contentView, not the glass view, so it layers above the video preview.
        let resizeHandle = ResizeHandleView(window: self)
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(resizeHandle)

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
                imageView.widthAnchor.constraint(equalToConstant: 20),
                imageView.heightAnchor.constraint(equalToConstant: 20)
            ])

            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
        }

        override func cursorUpdate(with _: NSEvent) {
            NSCursor.resizeLeftRight.set() // NSCursor has no public diagonal resize cursor
        }

        override func mouseDown(with _: NSEvent) {
            // Required to capture mouseDragged
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window = windowToResize else { return }

            // Drive resizing by horizontal movement for stability.
            let dX = event.deltaX
            var newWidth = window.frame.width + dX

            // Lock the 3:2 aspect ratio so the camera never distorts.
            let aspectRatio: CGFloat = 1.5

            let minWidth: CGFloat = 200
            let maxWidth: CGFloat = 800
            newWidth = max(minWidth, min(maxWidth, newWidth))

            let newHeight = newWidth / aspectRatio

            // macOS origin is bottom-left, so keep maxY fixed to anchor the top-left corner.
            let currentMaxY = window.frame.maxY
            let newY = currentMaxY - newHeight

            let newFrame = NSRect(
                x: window.frame.origin.x,
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
        // Must run on main thread for AVFoundation layer operations
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePreview(with: session)
            }
            return
        }

        if let currentLayer = previewLayer, currentLayer.session === session {
            return
        }

        // Disconnect the session before removing the layer to prevent use-after-free.
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

        guard let contentView = contentView else {
            AppLogger.camera.error("PiP: ContentView is nil!")
            return
        }

        let containerView = NSView(frame: contentView.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor

        let newLayer = AVCaptureVideoPreviewLayer(session: session)
        newLayer.frame = containerView.bounds
        newLayer.cornerRadius = PresenterOverlayLayout.cornerRadius
        newLayer.masksToBounds = true
        newLayer.videoGravity = .resizeAspectFill

        newLayer.isHidden = false
        newLayer.opacity = 1.0

        containerView.layer?.addSublayer(newLayer)
        containerView.autoresizingMask = [.width, .height]

        contentView.addSubview(containerView)

        if let glassView = contentView.subviews.first(where: { $0 is LiquidGlassNSView }) {
            contentView.addSubview(containerView, positioned: .above, relativeTo: glassView)
        } else {
             contentView.addSubview(containerView)
        }

        // Reorder with sortSubviews: removing and re-adding views breaks constraints and caused use-after-free crashes.
        contentView.sortSubviews({ (view1, view2, _) -> ComparisonResult in
            // Order: glassView < containerView < resizeHandle < controls
            let order: [String: Int] = [
                "LiquidGlassNSView": 0,
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

        // Defer to the next run loop so AVFoundation finishes its internal setup first.
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let connection = self.previewLayer?.connection,
                  self.previewLayer?.session === session else { return }

            // Must disable automaticallyAdjustsVideoMirroring BEFORE setting isVideoMirrored
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = UserDefaults.standard.bool(forKey: CameraPreviewMirroring.appStorageKey)
                AppLogger.camera.info("PiP: Configured video mirroring")
            }
        }
    }

    override func close() {
        // Close synchronously with animations off: animations still running at dealloc caused the _NSWindowTransformAnimation crash.

        cancellables.removeAll()

        // Disconnect the camera session first so AVFoundation stops calling back.
        previewLayer?.session = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        alphaValue = 0

        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        controlsHostingView?.isHidden = true
        controlsHostingView?.removeFromSuperview()
        controlsHostingView = nil

        previewView?.removeFromSuperview()
        previewView = nil

        CATransaction.commit()

        orderOut(nil)

        // Do not use asyncAfter here; it races with isReleasedWhenClosed.
        super.close()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)

        if let containerView = previewView,
           let layer = previewLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = containerView.bounds
            CATransaction.commit()
        }

        updateControlsForCurrentSize()
    }

    // MARK: - Double-Click to Cycle Size Presets
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        if event.clickCount == 2 {
            cycleToNextSize()
            ServiceContainer.shared.hapticsManager.impact()

            let currentPreset = PiPSize.fromWidth(frame.width)
            let sizeName = switch currentPreset {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            }
            ServiceContainer.shared.toastManager.show("PiP: \(sizeName)")
        }
    }

    /// Show hint about double-click resize on first use
    func showResizeHintIfNeeded() {
        let hasShownHint = UserDefaults.standard.bool(forKey: "pipResizeHintShown")
        if !hasShownHint {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                ServiceContainer.shared.toastManager.show("💡 Double-click PiP to resize")
                UserDefaults.standard.set(true, forKey: "pipResizeHintShown")
            }
        }
    }

    func snapToCorner(_ corner: ScreenCorner) {
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

    private func frameForLayout(_ layout: PresenterOverlayLayout, on screen: NSScreen) -> NSRect {
        let origin = origin(for: layout.corner, frameSize: CGSize(width: layout.width, height: layout.height), on: screen, margin: layout.margin)
        return NSRect(x: origin.x, y: origin.y, width: layout.width, height: layout.height)
    }

    private func origin(
        for corner: PresenterOverlayCorner,
        frameSize: CGSize,
        on screen: NSScreen,
        margin: CGFloat
    ) -> NSPoint {
        switch corner {
        case .bottomRight:
            return NSPoint(
                x: screen.frame.maxX - frameSize.width - margin,
                y: margin
            )
        case .bottomLeft:
            return NSPoint(x: margin, y: margin)
        case .topRight:
            return NSPoint(
                x: screen.frame.maxX - frameSize.width - margin,
                y: screen.frame.maxY - frameSize.height - margin
            )
        case .topLeft:
            return NSPoint(
                x: margin,
                y: screen.frame.maxY - frameSize.height - margin
            )
        }
    }
}

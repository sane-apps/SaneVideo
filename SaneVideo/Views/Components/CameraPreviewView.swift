//
//  CameraPreviewView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import OSLog
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context _: Context) {
        if nsView.session !== session {
            nsView.session = session
        }
    }

    // CRITICAL FIX: Proper cleanup to prevent use-after-free during autorelease
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) {
        // Disconnect session FIRST to stop frame delivery
        nsView.previewLayer.session = nil
        // Then remove the layer from the hierarchy
        nsView.previewLayer.removeFromSuperlayer()
    }

    // Internal NSView subclass to handle layout automatically
    class PreviewView: NSView {
        // CRITICAL FIX: nonisolated(unsafe) allows safe access from deinit
        // for cleanup. AVCaptureVideoPreviewLayer is not Sendable.
        // Made fileprivate to allow dismantleNSView to access it
        nonisolated(unsafe) fileprivate let previewLayer = AVCaptureVideoPreviewLayer()

        var session: AVCaptureSession? {
            get { previewLayer.session }
            set {
                // Ensure session assignment happens on Main thread (strictly Main Dispatch Queue for AVFoundation)
                if !Thread.isMainThread {
                    DispatchQueue.main.async { [weak self] in self?.session = newValue }
                    return
                }

                if previewLayer.session !== newValue {
                    previewLayer.session = newValue
                    AppLogger.camera.debug("CameraPreviewView: Session updated")

                    // CRITICAL FIX: Defer connection configuration with increased delay
                    // to allow frame delivery to stabilize before any modifications.
                    // macOS 26.2 appears to be stricter about queue expectations during first frame.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self = self, self.previewLayer.session === newValue, let connection = self.previewLayer.connection else { return }
                        AppLogger.camera.info("Configuring camera connection (after stabilization delay)...")
                        Self.safelyConfigureConnection(connection)
                    }
                }
            }
        }

        /// Safely configures the AVCaptureConnection
        private static func safelyConfigureConnection(_ connection: AVCaptureConnection) {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            AppLogger.camera.info("Configuring connection on macOS \(version.majorVersion).\(version.minorVersion)")

            // CRITICAL FIX: AVFoundation requires automaticallyAdjustsVideoMirroring to be disabled
            // BEFORE manually setting isVideoMirrored. Failure to do so causes NSInvalidArgumentException.
            if connection.isVideoMirroringSupported {
                // Step 1: Disable automatic adjustment (MUST come first)
                connection.automaticallyAdjustsVideoMirroring = false
                AppLogger.camera.info("Disabled automatic video mirroring adjustment")

                // Step 2: Now safe to set manual mirroring
                connection.isVideoMirrored = false
                AppLogger.camera.info("Set video mirrored to false")
            }

            if #available(macOS 14.0, *) {
                if connection.isVideoRotationAngleSupported(0.0) {
                    connection.videoRotationAngle = 0.0
                    AppLogger.camera.info("Set video rotation angle to 0.0")
                }
            }
        }

        init() {
            super.init(frame: .zero)
            setupLayer()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupLayer()
        }

        private func setupLayer() {
            wantsLayer = true
            if let layer = layer {
                layer.backgroundColor = NSColor.black.cgColor
                previewLayer.videoGravity = .resizeAspectFill
                layer.addSublayer(previewLayer)
            }
        }

        override func layout() {
            super.layout()
            // Ensure layer always fills the view
            if previewLayer.frame != bounds {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                previewLayer.frame = bounds
                CATransaction.commit()
            }
        }

        // CRITICAL FIX: Clean up layer on deallocation to prevent use-after-free
        // when the session is deallocated while the layer still references it
        deinit {
            previewLayer.session = nil
            previewLayer.removeFromSuperlayer()
        }
    }
}

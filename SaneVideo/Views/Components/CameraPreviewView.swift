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
    var isMirrored = CameraPreviewMirroring.defaultIsMirrored

    func makeNSView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.isMirrored = isMirrored
        view.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context _: Context) {
        nsView.isMirrored = isMirrored
        if nsView.session !== session {
            nsView.session = session
        } else {
            nsView.applyMirroringConfigurationSoon()
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
        var isMirrored = CameraPreviewMirroring.defaultIsMirrored {
            didSet {
                guard oldValue != isMirrored else { return }
                applyMirroringConfigurationSoon()
            }
        }

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

                    applyMirroringConfigurationSoon()
                }
            }
        }

        func applyMirroringConfigurationSoon() {
            let expectedSession = previewLayer.session
            let delays: [TimeInterval] = [0, 0.05, 0.2, 0.5]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self,
                          self.previewLayer.session === expectedSession,
                          let connection = self.previewLayer.connection
                    else { return }

                    AppLogger.camera.info("Configuring camera connection mirroring...")
                    Self.safelyConfigureConnection(connection, isMirrored: self.isMirrored)
                }
            }
        }

        /// Safely configures the AVCaptureConnection
        private static func safelyConfigureConnection(_ connection: AVCaptureConnection, isMirrored: Bool) {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            AppLogger.camera.info("Configuring connection on macOS \(version.majorVersion).\(version.minorVersion)")

            // CRITICAL FIX: AVFoundation requires automaticallyAdjustsVideoMirroring to be disabled
            // BEFORE manually setting isVideoMirrored. Failure to do so causes NSInvalidArgumentException.
            if connection.isVideoMirroringSupported {
                // Step 1: Disable automatic adjustment (MUST come first)
                connection.automaticallyAdjustsVideoMirroring = false
                AppLogger.camera.info("Disabled automatic video mirroring adjustment")

                // Step 2: Now safe to set manual mirroring
                connection.isVideoMirrored = isMirrored
                AppLogger.camera.info("Set video mirrored to \(isMirrored)")
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

enum CameraPreviewMirroring {
    static let appStorageKey = "MirrorCameraPreview"
    static let defaultIsMirrored = false
}

//
//  CameraPreviewView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import CoreImage
import OSLog
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let sampleBufferPublisher: AnyPublisher<CMSampleBuffer, Never>
    var isMirrored = CameraPreviewMirroring.defaultIsMirrored

    func makeCoordinator() -> Coordinator {
        Coordinator(sampleBufferPublisher: sampleBufferPublisher)
    }

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.isMirrored = isMirrored
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.isMirrored = isMirrored
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: PreviewView, coordinator: Coordinator) {
        coordinator.cancel()
        nsView.teardown()
    }

    final class Coordinator: @unchecked Sendable {
        private let sampleBufferPublisher: AnyPublisher<CMSampleBuffer, Never>
        private let renderQueue = DispatchQueue(label: "com.sanevideo.camera-preview.render", qos: .userInteractive)
        private let ciContext = CIContext()
        private var cancellable: AnyCancellable?
        private weak var previewView: PreviewView?

        init(sampleBufferPublisher: AnyPublisher<CMSampleBuffer, Never>) {
            self.sampleBufferPublisher = sampleBufferPublisher
        }

        func attach(to view: PreviewView) {
            previewView = view
            guard cancellable == nil else { return }

            cancellable = sampleBufferPublisher.sink { [weak self] sampleBuffer in
                self?.render(sampleBuffer)
            }
        }

        func cancel() {
            cancellable?.cancel()
            cancellable = nil
        }

        private func render(_ sampleBuffer: CMSampleBuffer) {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            nonisolated(unsafe) let unsafeImageBuffer = imageBuffer

            renderQueue.async { [weak self] in
                guard let self else { return }

                let ciImage = CIImage(cvPixelBuffer: unsafeImageBuffer)
                guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

                DispatchQueue.main.async { [weak self] in
                    self?.previewView?.display(cgImage)
                }
            }
        }
    }

    class PreviewView: NSView {
        private let previewLayer = CALayer()
        var isMirrored = CameraPreviewMirroring.defaultIsMirrored {
            didSet {
                applyMirroringConfiguration()
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
                previewLayer.backgroundColor = NSColor.black.cgColor
                previewLayer.contentsGravity = .resizeAspectFill
                layer.addSublayer(previewLayer)
            }
            applyMirroringConfiguration()
        }

        override func layout() {
            super.layout()
            if previewLayer.frame != bounds {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                previewLayer.frame = bounds
                applyMirroringConfiguration()
                CATransaction.commit()
            }
        }

        func display(_ image: CGImage) {
            previewLayer.contents = image
        }

        func teardown() {
            previewLayer.contents = nil
            previewLayer.removeFromSuperlayer()
        }

        private func applyMirroringConfiguration() {
            previewLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            previewLayer.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        }

    }
}

enum CameraPreviewMirroring {
    static let appStorageKey = "MirrorCameraPreview"
    static let defaultIsMirrored = false
}

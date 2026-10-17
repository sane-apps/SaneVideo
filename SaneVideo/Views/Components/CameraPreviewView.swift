import AVFoundation
import Combine
import SwiftUI

/// Shows live camera frames by handing each sample buffer to an AVSampleBufferDisplayLayer.
/// The frames stay on the GPU; converting them to CGImages cost a full core at 1080p60.
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
        private var cancellable: AnyCancellable?

        init(sampleBufferPublisher: AnyPublisher<CMSampleBuffer, Never>) {
            self.sampleBufferPublisher = sampleBufferPublisher
        }

        func attach(to view: PreviewView) {
            guard cancellable == nil else { return }
            let renderer = view.displayLayer.sampleBufferRenderer
            cancellable = sampleBufferPublisher.sink { sampleBuffer in
                Self.enqueue(sampleBuffer, on: renderer)
            }
        }

        func cancel() {
            cancellable?.cancel()
            cancellable = nil
        }

        private static func enqueue(_ sampleBuffer: CMSampleBuffer, on renderer: AVSampleBufferVideoRenderer) {
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
               CFArrayGetCount(attachments) > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            }
            if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
                renderer.flush()
            }
            if renderer.isReadyForMoreMediaData {
                renderer.enqueue(sampleBuffer)
            }
        }
    }

    final class PreviewView: NSView {
        let displayLayer = AVSampleBufferDisplayLayer()
        var isMirrored = CameraPreviewMirroring.defaultIsMirrored {
            didSet { applyMirroring() }
        }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            displayLayer.videoGravity = .resizeAspectFill
            displayLayer.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(displayLayer)
            applyMirroring()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            guard displayLayer.frame != bounds else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.frame = bounds
            applyMirroring()
            CATransaction.commit()
        }

        func teardown() {
            displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            displayLayer.removeFromSuperlayer()
        }

        private func applyMirroring() {
            displayLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            displayLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            displayLayer.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        }
    }
}

enum CameraPreviewMirroring {
    static let appStorageKey = "MirrorCameraPreview"
    static let defaultIsMirrored = false
}

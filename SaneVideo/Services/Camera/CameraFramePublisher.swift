//
//  CameraFramePublisher.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

@preconcurrency import AVFoundation
import Combine

final class CameraFramePublisher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    // Publisher for video frames
    let sampleBufferSubject = PassthroughSubject<CMSampleBuffer, Never>()

    // Callback for signal detection
    private var _onSignalReceived: (() -> Void)?
    private let lock = NSLock()

    var onSignalReceived: (() -> Void)? {
        get { lock.withLock { _onSignalReceived } }
        set { lock.withLock { _onSignalReceived = newValue } }
    }

    private var _hasReceivedSignal = false
    private var hasReceivedSignal: Bool {
        get { lock.withLock { _hasReceivedSignal } }
        set { lock.withLock { _hasReceivedSignal = newValue } }
    }

    nonisolated func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        autoreleasepool {
            if !hasReceivedSignal {
                hasReceivedSignal = true
                onSignalReceived?()
            }

            // Forward frames to subscribers
            sampleBufferSubject.send(sampleBuffer)
        }
    }

    func resetSignalStatus() {
        hasReceivedSignal = false
    }
}

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

    // DIAGNOSTIC: Track frame delivery rate from camera
    private var frameCount = 0
    private var lastLogTime: CFAbsoluteTime = 0
    private var firstFrameTime: CFAbsoluteTime = 0

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
                firstFrameTime = CFAbsoluteTimeGetCurrent()
                lastLogTime = firstFrameTime
                onSignalReceived?()
            }

            // DIAGNOSTIC: Track actual frame rate from camera hardware
            frameCount += 1
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastLogTime >= 2.0 {  // Log every 2 seconds
                let elapsed = now - firstFrameTime
                let fps = elapsed > 0 ? Double(frameCount) / elapsed : 0
                AppLogger.camera.info("📹 CameraFramePublisher: \(frameCount) frames in \(String(format: "%.1f", elapsed))s = \(String(format: "%.1f", fps)) fps from hardware")
                lastLogTime = now
            }

            // Forward frames to subscribers
            sampleBufferSubject.send(sampleBuffer)
        }
    }

    func resetSignalStatus() {
        hasReceivedSignal = false
    }
}

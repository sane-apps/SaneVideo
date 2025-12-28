//
//  VideoWriterProtocol.swift
//  SaneVideo
//
//  Protocol for VideoWriter to enable testability
//

import AVFoundation
import CoreMedia
import Foundation

/// @mockable
@RecordingActor
protocol VideoWriterProtocol: AnyObject, Sendable {
    // MARK: - State
    var isWriting: Bool { get }
    var error: Error? { get }
    var isReadyForData: Bool { get }

    // MARK: - Lifecycle
    func start(outputURL: URL) throws
    func startSession(at sourceTime: CMTime)
    func finish() async -> URL?

    // MARK: - Writing
    func writeVideo(sampleBuffer: CMSampleBuffer, presentationTime: CMTime, source: RecordingSource)
    func writeMicAudio(sampleBuffer: CMSampleBuffer)
    func writeSystemAudio(sampleBuffer: CMSampleBuffer)

    // MARK: - PiP Compositing
    func updateCameraFrame(_ pixelBuffer: CVPixelBuffer?)
    func updatePiPFrame(_ frame: CGRect?, screenFrame: CGRect?)
}

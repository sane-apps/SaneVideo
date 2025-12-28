//
//  ScreenRecorderProtocol.swift
//  SaneVideo
//
//  Protocol for ScreenRecorder to enable testability
//

import Combine
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// @mockable
@MainActor
protocol ScreenRecorderProtocol: AnyObject, Sendable {
    // MARK: - Publishers
    nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> { get }
    nonisolated var audioSampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> { get }
    nonisolated var micSampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> { get }

    // MARK: - State
    var activeStream: SCStream? { get }
    var isStopping: Bool { get }
    var baseFilter: SCContentFilter? { get }
    var recordingFrame: CGRect? { get }

    // MARK: - Callbacks
    var onStop: ((Error?) -> Void)? { get set }
    var onPresenterOverlayChanged: ((Bool) -> Void)? { get set }
    var onContentSelected: (() -> Void)? { get set }

    // MARK: - Public Interface
    func start(outputURL: URL?) async throws
    func stop() async
    func teardown()
    func updateContentFilter() async
    func handleContentSelected(filter: SCContentFilter) async
}

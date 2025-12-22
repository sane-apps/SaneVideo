//
//  CameraServiceProtocol.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import Foundation

@MainActor
protocol CameraServiceProtocol: AnyObject, Sendable {
    var isActive: Bool { get }
    var hasVideoSignal: Bool { get }
    var permissionGranted: Bool { get }
    var lastError: AppError? { get }
    var session: AVCaptureSession? { get }

    var isActivePublisher: AnyPublisher<Bool, Never> { get }
    var sessionPublisher: AnyPublisher<AVCaptureSession?, Never> { get }
    // Must be nonisolated to allow access from RecordingEngine's processingQueue
    nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> { get }

    func start(completion: @escaping @Sendable () -> Void)
    func stop()
    func toggle()
    func requestPermissionAgain()
    func restartSession()
}

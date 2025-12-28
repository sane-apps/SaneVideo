//
//  AudioServiceProtocol.swift
//  SaneVideo
//
//  Protocol for AudioService to enable testability
//

import AVFoundation
import Combine
import CoreMedia
import Foundation

/// @mockable
@MainActor
protocol AudioServiceProtocol: AnyObject, Sendable {
    // MARK: - State
    var isRunning: Bool { get }
    var permissionGranted: Bool { get }
    var currentMicID: String? { get }
    var availableMicrophones: [AVCaptureDevice] { get }

    // MARK: - Publishers
    nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> { get }
    nonisolated var audioLevelSubject: PassthroughSubject<Float, Never> { get }

    // MARK: - Discovery
    func refreshMicrophones()
    func ensureMicrophonesDiscovered()

    // MARK: - Permission
    func checkPermission()
    func requestPermission()

    // MARK: - Lifecycle
    func start()
    func stop()

    // MARK: - Configuration
    func switchMicrophone(to device: AVCaptureDevice)
}

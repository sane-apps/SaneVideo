//
//  PermissionManagerProtocol.swift
//  SaneVideo
//
//  Protocol for permission management
//

import AVFoundation
import Combine
import Foundation

/// @mockable
@MainActor
protocol PermissionManagerProtocol: AnyObject, Sendable {
    // MARK: - Status Properties
    var cameraStatus: PermissionStatus { get }
    var microphoneStatus: PermissionStatus { get }
    var screenRecordingStatus: PermissionStatus { get }

    // MARK: - Combine Publishers
    var cameraStatusPublisher: AnyPublisher<PermissionStatus, Never> { get }
    var microphoneStatusPublisher: AnyPublisher<PermissionStatus, Never> { get }
    var screenRecordingStatusPublisher: AnyPublisher<PermissionStatus, Never> { get }

    // MARK: - Check Permissions
    func checkAllPermissions()
    func checkCameraPermission()
    func checkMicrophonePermission()
    func checkScreenRecordingPermission()

    // MARK: - Request Permissions
    func requestCameraPermission() async -> Bool
    func requestMicrophonePermission() async -> Bool
    func requestScreenRecordingPermission()
    func requestAllPermissions() async -> [String: Bool]

    // MARK: - Settings
    func openSystemSettings()
    func openScreenRecordingSettings()

    // MARK: - Verification
    func verifyPermissionsForRecording(
        requiresCamera: Bool,
        requiresMicrophone: Bool,
        requiresScreenRecording: Bool
    ) -> Bool
}

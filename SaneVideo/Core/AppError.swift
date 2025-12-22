//
//  AppError.swift
//  SaneVideo
//
//  Unified error handling across the application

import Foundation

/// Unified error type for the entire application
enum AppError: LocalizedError, Identifiable {
    // Camera errors
    case cameraUnavailable
    case cameraPermissionDenied
    case cameraPermissionPromptShown
    case cameraPermissionRestricted
    case noCameraFound
    case cameraSetupFailed(Error)

    // Recording errors
    case recordingEngineError(String)
    case recordingStartFailed(Error)
    case recordingStopFailed(Error)
    case videoWriterError(Error)
    case audioSetupFailed(Error)
    case microphonePermissionDenied
    case microphonePermissionPromptShown
    case microphonePermissionRestricted

    // Export errors
    case exportFailed(Error)
    case exportCancelled
    case compositionFailed(Error)

    // File/Project errors
    case fileAccessDenied
    case projectLoadFailed(Error)
    case projectSaveFailed(Error)
    case invalidProjectData

    // Screen capture errors
    case screenCaptureUnavailable  // User cancelled picker or system error

    // Unknown
    case captionGenerationFailed(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        // Camera
        case .cameraUnavailable:
            "Camera is not available"
        case .cameraPermissionDenied:
            "Camera permission denied"
        case .cameraPermissionRestricted:
            "Camera access is restricted"
        case .noCameraFound:
            "No camera device found on this Mac"
        case let .cameraSetupFailed(error):
            "Failed to setup camera: \(error.localizedDescription)"
        case .cameraPermissionPromptShown:
            "Camera permission requested"
        // Recording
        case let .recordingEngineError(message):
            "Recording error: \(message)"
        case let .recordingStartFailed(error):
            "Failed to start recording: \(error.localizedDescription)"
        case let .recordingStopFailed(error):
            "Failed to stop recording: \(error.localizedDescription)"
        case let .videoWriterError(error):
            "Video writing error: \(error.localizedDescription)"
        case let .audioSetupFailed(error):
            "Audio setup failed: \(error.localizedDescription)"
        case .microphonePermissionDenied:
             "Microphone permission denied"
        case .microphonePermissionPromptShown:
             "Microphone permission requested"
        case .microphonePermissionRestricted:
             "Microphone access restricted"
        // Export
        case let .exportFailed(error):
            "Export failed: \(error.localizedDescription)"
        case .exportCancelled:
            "Export was cancelled"
        case let .compositionFailed(error):
            "Failed to compose video: \(error.localizedDescription)"
        // File/Project
        case .fileAccessDenied:
            "File access denied"
        case let .projectLoadFailed(error):
            "Failed to load project: \(error.localizedDescription)"
        case let .projectSaveFailed(error):
            "Failed to save project: \(error.localizedDescription)"
        case .invalidProjectData:
            "Invalid project data"
        // Screen capture
        case .screenCaptureUnavailable:
            "Screen recording unavailable. Please try again."
        case let .captionGenerationFailed(reason):
            "Caption generation failed: \(reason)"
        case let .unknown(error):
            "An error occurred: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cameraPermissionDenied, .cameraPermissionRestricted:
            "Open System Settings > Privacy & Security > Camera and enable access for SaneVideo."
        case .cameraPermissionPromptShown:
            "Please click 'Allow' in the system dialog to enable camera access."
        case .microphonePermissionDenied, .microphonePermissionRestricted:
            "Open System Settings > Privacy & Security > Microphone and enable access for SaneVideo."
        case .microphonePermissionPromptShown:
            "Please click 'Allow' in the system dialog to enable microphone access."

        case .noCameraFound:
            "Connect an external camera or use screen recording mode."
        case .cameraUnavailable:
            "The camera is in use by another app. Close other apps using the camera and try again."
        case .cameraSetupFailed:
            "Camera setup failed. Try: 1) Restart the app, 2) Check if another app is using the camera, 3) Restart your Mac if the issue persists."
        case .fileAccessDenied:
            "File access denied. Try: 1) Grant access when prompted, 2) Drag the file into the app, 3) Check file permissions in Finder."
        case .projectLoadFailed:
            "Failed to load project. Try: 1) Check if the project file is corrupted, 2) Restore from backup, 3) Create a new project."
        case .projectSaveFailed:
            "Failed to save project. Try: 1) Check disk space, 2) Verify write permissions, 3) Try saving to a different location."
        case .invalidProjectData:
            "Project file is corrupted. Try: 1) Restore from backup, 2) Create a new project, 3) Contact support if you have a backup."
        case .recordingStartFailed:
            "Failed to start recording. Try: 1) Check camera/microphone permissions, 2) Restart the app, 3) Check available disk space."
        case .recordingStopFailed:
            "Failed to stop recording. The recording may be saved. Try: 1) Check the Recordings folder, 2) Restart the app if needed."
        case .videoWriterError:
            "Video writing error. Try: 1) Check disk space (need at least 1GB free), 2) Close other apps, 3) Restart the app."
        case .audioSetupFailed:
            "Audio setup failed. Try: 1) Check microphone permissions, 2) Select a different microphone, 3) Restart the app."
        case .exportFailed:
            "Export failed. Try: 1) Check disk space, 2) Try a lower resolution, 3) Close other apps, 4) Restart the app."
        case .compositionFailed:
            "Failed to compose video. Try: 1) Remove problematic clips, 2) Check file integrity, 3) Try exporting individual clips."
        case .screenCaptureUnavailable:
            "Screen capture unavailable. The system picker may have been cancelled. Click 'Share Screen' to try again."
        case let .captionGenerationFailed(reason):
            "Caption generation failed: \(reason). Try: 1) Check microphone permissions, 2) Ensure audio track exists, 3) Try again."
        case let .recordingEngineError(message):
            "Recording error: \(message). Try: 1) Check permissions, 2) Restart the app, 3) Check disk space."
        case .exportCancelled:
            nil
        case .unknown:
            "An unexpected error occurred. Try: 1) Restart the app, 2) Check system logs (⌘L), 3) Contact support if it persists."
        }
    }

    /// Whether this error should be logged to diagnostics
    var shouldLog: Bool {
        switch self {
        case .exportCancelled:
            false
        default:
            true
        }
    }

    var id: String {
        String(reflecting: self)
    }
}

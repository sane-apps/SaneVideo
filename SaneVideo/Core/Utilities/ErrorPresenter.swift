//
//  ErrorPresenter.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Combine
import SwiftUI

/// Centralized error presenter for SwiftUI views
/// CRITICAL FIX: Implements error queueing to prevent overwriting errors
/// SWIFT 6 FIX: @MainActor required for UI-driving state (error queue accessed from SwiftUI)
@MainActor
@Observable
class ErrorPresenter {
    init() {}
    
    // MARK: - Public API
    
    /// The currently displayed error
    /// CRITICAL FIX: Computed from queue, but settable for SwiftUI binding
    var activeError: AppError? {
        get {
            errorQueue.first
        }
        set {
            // When SwiftUI sets this to nil (dismiss), remove from queue
            if newValue == nil && !errorQueue.isEmpty {
                errorQueue.removeFirst()
            } else if let error = newValue {
                // If setting a new error directly, queue it
                queueError(error)
            }
        }
    }
    
    /// CRITICAL FIX: Error queue to prevent overwriting
    /// Errors are shown one at a time, with critical errors prioritized
    private var errorQueue: [AppError] = []
    
    /// Maximum queue size to prevent memory issues
    private let maxQueueSize = 10

    /// Present an error to the user
    /// - Parameter error: The error to present. If it's not an AppError, it will be wrapped in .unknown
    /// CRITICAL FIX: Errors are queued instead of overwriting
    func present(_ error: Error) {
        let appError: AppError
        if let error = error as? AppError {
            // Ignore implicit prompt triggers to avoid redundant alerts
            switch error {
            case .cameraPermissionPromptShown,
                 .microphonePermissionPromptShown:
                return
            default:
                appError = error
            }
        } else {
            appError = .unknown(error)
        }

        // Log the error automatically when presented
        AppLogger.logError(appError)
        
        // CRITICAL FIX: Queue error instead of overwriting
        queueError(appError)
    }

    /// Dismiss the current error and show the next one in queue
    func dismiss() {
        guard !errorQueue.isEmpty else { return }
        
        // Remove the current error
        errorQueue.removeFirst()
        
        // If there are more errors, the activeError will automatically update
        // (it's computed from errorQueue.first)
    }
    
    // MARK: - Private Helpers
    
    /// CRITICAL FIX: Queue error with priority handling
    /// Critical errors are inserted at the front, others are appended
    private func queueError(_ error: AppError) {
        // Prevent duplicate errors in quick succession
        if let lastError = errorQueue.last,
           isDuplicate(error, lastError) {
            AppLogger.general.debug("Skipping duplicate error: \(error.localizedDescription)")
            return
        }
        
        // CRITICAL FIX: Prioritize critical errors
        if isCriticalError(error) {
            // Insert critical errors at the front
            errorQueue.insert(error, at: 0)
        } else {
            // Append non-critical errors
            errorQueue.append(error)
        }
        
        // CRITICAL FIX: Limit queue size to prevent memory issues
        if errorQueue.count > maxQueueSize {
            // Remove oldest non-critical errors first
            let criticalCount = errorQueue.prefix { isCriticalError($0) }.count
            if criticalCount < maxQueueSize {
                // Remove oldest non-critical error
                errorQueue.removeLast()
            } else {
                // All errors are critical, remove oldest
                errorQueue.removeLast()
            }
        }
        
        AppLogger.general.info("📋 Error queued. Queue size: \(errorQueue.count)")
    }
    
    /// Check if error is critical (should be shown immediately)
    private func isCriticalError(_ error: AppError) -> Bool {
        // Critical errors that should be shown immediately
        switch error {
        case .projectSaveFailed,
             .projectLoadFailed,
             .recordingEngineError,
             .cameraPermissionDenied,
             .microphonePermissionDenied,
             .cameraPermissionRestricted,
             .microphonePermissionRestricted,
             .screenCaptureUnavailable,
             .compositionFailed,
             .exportFailed:
            return true
        default:
            return false
        }
    }
    
    /// Check if two errors are duplicates (same type and message)
    private func isDuplicate(_ error1: AppError, _ error2: AppError) -> Bool {
        // Simple duplicate check - same error type
        // Could be enhanced to check error messages too
        switch (error1, error2) {
        case (.projectSaveFailed, .projectSaveFailed),
             (.projectLoadFailed, .projectLoadFailed),
             (.recordingEngineError, .recordingEngineError),
             (.cameraPermissionDenied, .cameraPermissionDenied),
             (.microphonePermissionDenied, .microphonePermissionDenied),
             (.exportFailed, .exportFailed),
             (.compositionFailed, .compositionFailed):
            return true
        default:
            return false
        }
    }
    
    /// Clear all queued errors
    func clearAll() {
        errorQueue.removeAll()
    }
}

import Combine
import SwiftUI

/// Queues errors so a new one does not replace one still on screen.
/// MainActor because SwiftUI reads the queue.
@MainActor
@Observable
class ErrorPresenter {
    init() {}
    
    // MARK: - Public API
    
    /// Computed from the queue but settable so SwiftUI can bind to it.
    var activeError: AppError? {
        get {
            errorQueue.first
        }
        set {
            // When SwiftUI sets this to nil (dismiss), remove from queue
            if newValue == nil && !errorQueue.isEmpty {
                errorQueue.removeFirst()
            } else if let error = newValue {
                queueError(error)
            }
        }
    }
    
    /// Errors are shown one at a time, with critical errors prioritized
    private var errorQueue: [AppError] = []
    
    private let maxQueueSize = 10

    /// - Parameter error: The error to present. If it's not an AppError, it will be wrapped in .unknown
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

        AppLogger.logError(appError)
        
        queueError(appError)
    }

    /// Dismiss the current error and show the next one in queue
    func dismiss() {
        guard !errorQueue.isEmpty else { return }
        
        errorQueue.removeFirst()
        
        // activeError reads errorQueue.first, so the next error shows on its own.
    }
    
    // MARK: - Private Helpers
    
    /// Critical errors are inserted at the front, others are appended
    private func queueError(_ error: AppError) {
        // Prevent duplicate errors in quick succession
        if let lastError = errorQueue.last,
           isDuplicate(error, lastError) {
            AppLogger.general.debug("Skipping duplicate error: \(error.localizedDescription)")
            return
        }
        
        if isCriticalError(error) {
            errorQueue.insert(error, at: 0)
        } else {
            errorQueue.append(error)
        }
        
        // When queue is full, remove oldest non-critical error to make room
        if errorQueue.count > maxQueueSize {
            if let indexToRemove = errorQueue.firstIndex(where: { !isCriticalError($0) }) {
                let removed = errorQueue.remove(at: indexToRemove)
                AppLogger.general.warning("⚠️ Error queue full, dropped: \(removed.localizedDescription)")
            } else {
                let removed = errorQueue.removeFirst()
                AppLogger.general.warning("⚠️ Error queue full (all critical), dropped oldest: \(removed.localizedDescription)")
            }
        }
        
        AppLogger.general.info("📋 Error queued. Queue size: \(errorQueue.count)")
    }
    
    /// Check if error is critical (should be shown immediately)
    private func isCriticalError(_ error: AppError) -> Bool {
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
    
    /// Matches on error type only, not message.
    private func isDuplicate(_ error1: AppError, _ error2: AppError) -> Bool {
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
    
    func clearAll() {
        errorQueue.removeAll()
    }
}

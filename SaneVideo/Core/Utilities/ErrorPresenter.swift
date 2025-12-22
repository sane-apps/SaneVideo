//
//  ErrorPresenter.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Combine
import SwiftUI

/// Centralized error presenter for SwiftUI views
@Observable
class ErrorPresenter {
    init() {}
    var activeError: AppError?

    /// Present an error to the user
    /// - Parameter error: The error to present. If it's not an AppError, it will be wrapped in .unknown
    func present(_ error: Error) {
        if let appError = error as? AppError {
            // Ignore implicit prompt triggers to avoid redundant alerts
            switch appError {
            case .cameraPermissionPromptShown,
                 .microphonePermissionPromptShown:
                return
            default:
                activeError = appError
            }
        } else {
            activeError = .unknown(error)
        }

        // Log the error automatically when presented
        if let appError = activeError {
            AppLogger.logError(appError)
        }
    }

    /// Dismiss the current error
    func dismiss() {
        activeError = nil
    }
}

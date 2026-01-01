//
//  ToastManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Combine
import Foundation
import SwiftUI

@MainActor
@Observable
class ToastManager {

    enum AlertType {
        case info, success, error
    }
    var toastMessage: String?

    // CRITICAL FIX: Queue system for rapid successive toasts
    private var messageQueue: [String] = []
    private var isShowingToast = false

    init() {}

    func show(_ message: String, type: AlertType = .info) {
        Task { @MainActor in
            // Log for debugging
            if type == .error {
                AppLogger.uiLog.error("Toast Error: \(message)")
            } else {
                AppLogger.uiLog.debug("Toast: \(message)")
            }

            // If already showing, queue this message (max 3 to prevent buildup)
            if isShowingToast {
                if messageQueue.count < 3 {
                    messageQueue.append(message)
                } else {
                    // Replace last queued message with latest
                    messageQueue[messageQueue.count - 1] = message
                    AppLogger.uiLog.debug("Toast queue full, replaced last with: \(message)")
                }
                return
            }

            await showMessage(message)
        }
    }

    private func showMessage(_ message: String) async {
        isShowingToast = true

        // Clear first to allow re-triggering same message
        if toastMessage != nil {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms blink
        }

        toastMessage = message

        // Allow message to display briefly before checking queue
        try? await Task.sleep(nanoseconds: 800_000_000) // 800ms minimum display

        // Check if there's a queued message
        if let nextMessage = messageQueue.first {
            messageQueue.removeFirst()
            await showMessage(nextMessage)
        } else {
            isShowingToast = false
        }
    }

    func clear() {
        toastMessage = nil
        messageQueue.removeAll()
        isShowingToast = false
    }
}

//
//  ProjectState+Cancellation.swift
//  SaneVideo
//
//  Cancellation support for long-running operations
//

import Foundation

extension ProjectState {
    /// Cancel any ongoing processing operation
    func cancelProcessing() async {
        // Cancel the task if it exists
        currentProcessingTask?.cancel()
        currentProcessingTask = nil

        await MainActor.run {
            // ENHANCEMENT: Use transaction-based cancellation
            let activeCount = activeTransactionCount
            cancelAllTransactions() // Use transaction system

            if activeCount > 0 {
                AppLogger.project.info("🚫 Cancelled \(activeCount) active transaction(s)")
                ServiceContainer.shared.toastManager.show("Operation cancelled", type: .info)
            }
        }
    }

    /// Cancel a specific transaction by ID
    /// - Parameter transactionId: The transaction ID to cancel
    func cancelTransactionById(_ transactionId: UUID) async {
        await MainActor.run {
            if isValidTransaction(transactionId) {
                cancelTransaction(transactionId) // Calls the method from ProjectState+Transactions
                AppLogger.project.info("🚫 Cancelled transaction: \(transactionId.uuidString.prefix(8))")
            }
        }
    }

    /// Store the processing task for cancellation
    func setProcessingTask(_ task: Task<Void, Error>) {
        currentProcessingTask = task
    }
}

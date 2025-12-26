//
//  ProjectState+Transactions.swift
//  SaneVideo
//
//  Transaction-based orchestration system for AI processing operations
//  Replaces fragile boolean isProcessing flag with multi-transaction tracking
//

import Foundation

extension ProjectState {
    // MARK: - Transaction Management

    /// Begin a new processing transaction
    /// Returns a transaction ID that can be used to bypass guards
    /// - Returns: UUID for the new transaction
    @discardableResult
    func beginTransaction() -> UUID {
        let transactionId = UUID()
        let wasProcessing = isProcessing
        processingTransactions.insert(transactionId)
        transactionProgress[transactionId] = 0.0

        // Log transaction start if this is the first one
        if !wasProcessing {
            AppLogger.project.debug("🔄 Transaction started: \(transactionId.uuidString.prefix(8))")
        }

        return transactionId
    }

    /// End a processing transaction
    /// - Parameter transactionId: The transaction ID to end
    func endTransaction(_ transactionId: UUID) {
        let wasProcessing = isProcessing
        processingTransactions.remove(transactionId)
        transactionProgress.removeValue(forKey: transactionId)

        // Update overall progress from remaining transactions
        updateOverallProgress()

        // Log transaction end if this was the last one
        if wasProcessing && !isProcessing {
            AppLogger.project.debug("✅ Transaction ended: \(transactionId.uuidString.prefix(8))")

            // Clear progress/status when all transactions complete
            processingProgress = 1.0
            processingStatus = nil
        }
    }

    /// Check if a transaction ID is valid (exists in active transactions)
    /// - Parameter transactionId: The transaction ID to validate
    /// - Returns: True if the transaction is active
    func isValidTransaction(_ transactionId: UUID?) -> Bool {
        guard let transactionId = transactionId else { return false }
        return processingTransactions.contains(transactionId)
    }

    /// Cancel all active transactions
    /// Used when user explicitly cancels operations
    func cancelAllTransactions() {
        let count = processingTransactions.count
        let transactionIds = Array(processingTransactions)
        processingTransactions.removeAll()
        transactionProgress.removeAll()
        processingProgress = 0.0
        processingStatus = nil

        if count > 0 {
            AppLogger.project.info("🚫 Cancelled \(count) active transaction(s)")
            // Log each cancelled transaction for debugging
            for transactionId in transactionIds {
                AppLogger.project.debug("🚫 Cancelled transaction: \(transactionId.uuidString.prefix(8))")
            }
        }
    }

    /// Cancel a specific transaction
    /// - Parameter transactionId: The transaction ID to cancel
    func cancelTransaction(_ transactionId: UUID) {
        if processingTransactions.remove(transactionId) != nil {
            transactionProgress.removeValue(forKey: transactionId)
            updateOverallProgress()
            AppLogger.project.debug("🚫 Cancelled transaction: \(transactionId.uuidString.prefix(8))")
        }
    }

    /// Update progress for a specific transaction
    /// - Parameters:
    ///   - transactionId: The transaction ID
    ///   - progress: Progress value (0.0-1.0)
    func updateTransactionProgress(_ transactionId: UUID, progress: Double) {
        guard processingTransactions.contains(transactionId) else { return }
        transactionProgress[transactionId] = max(0.0, min(1.0, progress))
        updateOverallProgress()
    }

    /// Get progress for a specific transaction
    /// - Parameter transactionId: The transaction ID
    /// - Returns: Progress value (0.0-1.0) or nil if transaction doesn't exist
    func getTransactionProgress(_ transactionId: UUID) -> Double? {
        return transactionProgress[transactionId]
    }

    /// Update overall progress from all active transactions
    private func updateOverallProgress() {
        guard !transactionProgress.isEmpty else {
            processingProgress = 0.0
            return
        }

        // Calculate average progress across all active transactions
        let totalProgress = transactionProgress.values.reduce(0.0, +)
        let averageProgress = totalProgress / Double(transactionProgress.count)
        processingProgress = averageProgress
    }

    /// Get count of active transactions (for debugging/monitoring)
    var activeTransactionCount: Int {
        processingTransactions.count
    }

    // MARK: - Guard Helpers

    /// Check if an operation should be blocked by processing state
    /// - Parameter transactionId: Optional transaction ID. If provided and valid, the operation is allowed even if processing is active
    /// - Returns: True if the operation should be blocked, false if it should proceed
    func shouldBlockOperation(transactionId: UUID? = nil) -> Bool {
        // If a valid transaction ID is provided, allow the operation
        if let transactionId = transactionId, isValidTransaction(transactionId) {
            return false
        }

        // Otherwise, block if processing is active
        return isProcessing
    }
}

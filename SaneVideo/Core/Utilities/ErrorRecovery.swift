//
//  ErrorRecovery.swift
//  SaneVideo
//
//  Error recovery and retry mechanisms for robust operations
//

import Foundation

/// Error recovery strategies
enum RecoveryStrategy {
    case retry(maxAttempts: Int, delay: TimeInterval)
    case fallback(operation: @Sendable () async throws -> Void)
    case skip
    case fail
}

/// Result of a recovery attempt
enum RecoveryResult {
    case success
    case retry
    case fallback
    case failed(Error)
}

/// Determines if an error is recoverable (transient vs permanent)
func isRecoverableError(_ error: Error) -> Bool {
    // Network errors are usually transient
    if let urlError = error as? URLError {
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }
    
    // Timeout errors are recoverable
    if error is TimeoutError {
        return true
    }
    
    // Cancellation is not recoverable
    if error is CancellationError {
        return false
    }
    
    // Default: assume recoverable for retry
    return true
}

/// Retries an operation with exponential backoff
func retryOperation<T: Sendable>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?
    var delay = initialDelay
    
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            
            // Don't retry if error is not recoverable
            guard isRecoverableError(error) else {
                throw error
            }
            
            // Don't retry on last attempt
            guard attempt < maxAttempts else {
                break
            }
            
            // Exponential backoff
            AppLogger.general.warning("⚠️ Operation failed (attempt \(attempt)/\(maxAttempts)), retrying in \(String(format: "%.1f", delay))s: \(error.localizedDescription)")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay *= 2.0 // Exponential backoff
        }
    }
    
    throw lastError ?? NSError(domain: "ErrorRecovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation failed after \(maxAttempts) attempts"])
}

/// Executes an operation with automatic recovery
func executeWithRecovery<T: Sendable>(
    strategy: RecoveryStrategy,
    operation: @escaping @Sendable () async throws -> T,
    fallback: (@Sendable () async throws -> T)? = nil
) async throws -> T {
    switch strategy {
    case .retry(let maxAttempts, let delay):
        return try await retryOperation(maxAttempts: maxAttempts, initialDelay: delay, operation: operation)
        
    case .fallback(let fallbackOp):
        do {
            return try await operation()
        } catch {
            AppLogger.general.warning("⚠️ Primary operation failed, using fallback: \(error.localizedDescription)")
            try await fallbackOp()
            throw error // Re-throw original error if fallback doesn't help
        }
        
    case .skip:
        do {
            return try await operation()
        } catch {
            AppLogger.general.warning("⚠️ Operation failed, skipping: \(error.localizedDescription)")
            throw error
        }
        
    case .fail:
        return try await operation()
    }
}


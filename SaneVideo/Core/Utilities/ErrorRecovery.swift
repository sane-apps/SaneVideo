import Foundation

enum RecoveryStrategy {
    case retry(maxAttempts: Int, delay: TimeInterval)
    case fallback(operation: @Sendable () async throws -> Void)
    case skip
    case fail
}

enum RecoveryResult {
    case success
    case retry
    case fallback
    case failed(Error)
}

/// Determines if an error is recoverable (transient vs permanent)
func isRecoverableError(_ error: Error) -> Bool {
    if error is CancellationError {
        return false
    }
    
    // Network errors are usually transient
    if let urlError = error as? URLError {
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
            return true
        case .fileDoesNotExist, .fileIsDirectory, .cannotDecodeContentData, .cannotDecodeRawData:
            return false // Permanent file errors
        default:
            return false // Default to non-recoverable for network errors
        }
    }
    
    if let cocoaError = error as? CocoaError {
        switch cocoaError.code {
        case .fileReadNoPermission, .fileWriteNoPermission:
            return false // Permission errors are usually permanent
        case .fileReadCorruptFile, .fileWriteFileExists:
            return false // Corruption/conflict errors are permanent
        case .fileReadNoSuchFile:
            return false // Missing file errors are permanent
        default:
            // For other Cocoa errors, be conservative
            // Note: CocoaError doesn't have a .timedOut case - timeout is handled separately
            return false
        }
    }
    
    if error is TimeoutError {
        return true
    }
    
    if let nsError = error as NSError? {
        if nsError.domain == NSPOSIXErrorDomain {
            // POSIX errors like ENOENT, EACCES are permanent
            return false
        }
        
        // Most app errors are permanent (invalid format, missing files, etc.)
        return false
    }
    
    // Default to non-recoverable (conservative approach)
    // Only retry errors we explicitly know are transient
    return false
}

/// Retries an operation with exponential backoff
func retryOperation<T: Sendable>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    maxDelay: TimeInterval = 5.0,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?
    var delay = initialDelay
    
    for attempt in 1...maxAttempts {
        try Task.checkCancellation()
        
        do {
            return try await operation()
        } catch {
            lastError = error
            
            guard isRecoverableError(error) else {
                AppLogger.general.info("Operation failed with non-recoverable error: \(error.localizedDescription)")
                throw error
            }
            
            guard attempt < maxAttempts else {
                break
            }
            
            let cappedDelay = min(delay, maxDelay)
            
            // Log as info (not warning) since retry is expected for transient errors
            AppLogger.general.info("⚠️ Operation failed (attempt \(attempt)/\(maxAttempts)), retrying in \(String(format: "%.1f", cappedDelay))s: \(error.localizedDescription)")
            
            // Check for cancellation during sleep
            try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
            
            delay = min(delay * 2.0, maxDelay)
        }
    }
    
    throw lastError ?? NSError(domain: "ErrorRecovery", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation failed after \(maxAttempts) attempts"])
}

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
            // Fallback doesn't return value, just executes
            try await fallbackOp()
            throw error
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

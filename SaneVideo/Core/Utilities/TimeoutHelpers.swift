//
//  TimeoutHelpers.swift
//  SaneVideo
//
//  Timeout and cancellation utilities for robust async operations
//

import Foundation

/// Wraps an async operation with a timeout
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Operation task
        group.addTask {
            try await operation()
        }
        
        // Timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timeout(seconds: seconds)
        }
        
        // Return first result, cancel the other
        guard let result = try await group.next() else {
            throw TimeoutError.timeout(seconds: seconds)
        }
        group.cancelAll()
        return result
    }
}

/// Wraps an async operation with timeout and cancellation support
func withTimeoutAndCancellation<T: Sendable>(
    seconds: TimeInterval,
    cancellation: @escaping @Sendable () -> Bool,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Operation task
        group.addTask {
            try await operation()
        }
        
        // Timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timeout(seconds: seconds)
        }
        
        // Cancellation check task
        group.addTask {
            while !Task.isCancelled {
                if cancellation() {
                    throw CancellationError()
                }
                try await Task.sleep(nanoseconds: 100_000_000) // Check every 100ms
            }
            throw CancellationError()
        }
        
        // Return first result, cancel the other
        guard let result = try await group.next() else {
            throw TimeoutError.timeout(seconds: seconds)
        }
        group.cancelAll()
        return result
    }
}

enum TimeoutError: Error, LocalizedError {
    case timeout(seconds: TimeInterval)
    
    var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Operation timed out after \(Int(seconds)) seconds"
        }
    }
}

/// Progress heartbeat to detect hangs
actor ProgressHeartbeat {
    private var lastProgressTime: Date = Date()
    private var lastProgressValue: Double = 0.0
    private let timeoutSeconds: TimeInterval
    
    init(timeoutSeconds: TimeInterval = 30.0) {
        self.timeoutSeconds = timeoutSeconds
    }
    
    func updateProgress(_ value: Double) {
        lastProgressTime = Date()
        lastProgressValue = value
    }
    
    func checkForHang() throws {
        let elapsed = Date().timeIntervalSince(lastProgressTime)
        if elapsed > timeoutSeconds {
            // Check if progress actually changed
            if lastProgressValue > 0 {
                throw TimeoutError.timeout(seconds: timeoutSeconds)
            }
        }
    }
}


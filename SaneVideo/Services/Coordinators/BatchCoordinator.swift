//
//  BatchCoordinator.swift
//  SaneVideo
//
//  Service for coordinating parallel batch operations
//  Provides consistent concurrency limits, progress tracking, and error handling
//

import Foundation

/// Result of a batch operation on a single item
struct BatchItemResult<T: Sendable>: @unchecked Sendable {
    let item: T
    let success: Bool
    let error: Error?
}

/// Configuration for batch operations
struct BatchConfig {
    /// Maximum number of concurrent operations (default: 4)
    let maxConcurrent: Int

    /// Whether to continue on individual item failures (default: true)
    let continueOnError: Bool

    /// Custom progress update interval in seconds (default: 0.1)
    let progressUpdateInterval: TimeInterval

    static let `default` = BatchConfig(
        maxConcurrent: 4,
        continueOnError: true,
        progressUpdateInterval: 0.1
    )

    /// Configuration optimized for I/O-bound operations (e.g., export)
    static let ioBound = BatchConfig(
        maxConcurrent: 2,
        continueOnError: true,
        progressUpdateInterval: 0.2
    )
}

/// Coordinator for parallel batch operations
/// Uses static methods for stateless batch processing
enum BatchCoordinator {

    /// Execute a batch operation with parallel processing
    /// - Parameters:
    ///   - items: Array of items to process
    ///   - config: Batch configuration (default: 4 concurrent workers)
    ///   - operation: Async operation to perform on each item
    ///   - progressHandler: Optional progress callback (current index, total count)
    /// - Returns: Array of results for each item
    static func execute<T: Sendable>(
        items: [T],
        config: BatchConfig = .default,
        operation: @escaping @Sendable (T, Int) async throws -> Void,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [BatchItemResult<T>] {
        guard !items.isEmpty else { return [] }

        let total = items.count
        // Pre-allocate results array with correct order
        var results: [BatchItemResult<T>?] = Array(repeating: nil, count: total)
        var completedCount = 0
        var lastProgressUpdate = Date()

        // Use TaskGroup for parallel execution with concurrency limit
        await withTaskGroup(of: (Int, Result<Void, Error>).self) { group in
            var activeTasks = 0

            for (index, item) in items.enumerated() {
                // Wait for available slot if at capacity
                if activeTasks >= config.maxConcurrent {
                    let (completedIndex, result) = await group.next()!
                    activeTasks -= 1
                    completedCount += 1

                    // Record result at correct index
                    switch result {
                    case .success:
                        results[completedIndex] = BatchItemResult(item: items[completedIndex], success: true, error: nil)
                    case .failure(let error):
                        results[completedIndex] = BatchItemResult(item: items[completedIndex], success: false, error: error)
                    }

                    // Update progress (throttled)
                    let now = Date()
                    if now.timeIntervalSince(lastProgressUpdate) >= config.progressUpdateInterval {
                        progressHandler?(completedCount, total)
                        lastProgressUpdate = now
                    }
                }

                // Add task for current item
                let itemIndex = index
                group.addTask {
                    do {
                        try await operation(item, itemIndex)
                        return (itemIndex, .success(()))
                    } catch {
                        return (itemIndex, .failure(error))
                    }
                }
                activeTasks += 1
            }

            // Wait for remaining tasks
            while activeTasks > 0 {
                let (completedIndex, result) = await group.next()!
                activeTasks -= 1
                completedCount += 1

                // Record result at correct index
                switch result {
                case .success:
                    results[completedIndex] = BatchItemResult(item: items[completedIndex], success: true, error: nil)
                case .failure(let error):
                    results[completedIndex] = BatchItemResult(item: items[completedIndex], success: false, error: error)
                }

                // Update progress
                let now = Date()
                if now.timeIntervalSince(lastProgressUpdate) >= config.progressUpdateInterval {
                    progressHandler?(completedCount, total)
                    lastProgressUpdate = now
                }
            }
        }

        // Final progress update
        progressHandler?(total, total)

        // Convert to non-optional array (all results should be filled)
        return results.compactMap { $0 }
    }

    /// Execute batch operation with simplified API (throws on failure)
    /// - Parameters:
    ///   - items: Array of items to process
    ///   - config: Batch configuration
    ///   - operation: Async operation to perform on each item
    ///   - progressHandler: Optional progress callback
    static func executeAndThrow<T: Sendable>(
        items: [T],
        config: BatchConfig = .default,
        operation: @escaping @Sendable (T, Int) async throws -> Void,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        let results = await execute(
            items: items,
            config: config,
            operation: operation,
            progressHandler: progressHandler
        )

        // Check for failures if continueOnError is false
        if !config.continueOnError {
            let failures = results.filter { !$0.success }
            if !failures.isEmpty {
                throw BatchError.operationFailed(failures.count, failures.first?.error)
            }
        }
    }
}

/// Errors for batch operations
enum BatchError: LocalizedError {
    case operationFailed(Int, Error?)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let count, let error):
            if let error = error {
                return "Batch operation failed: \(count) item(s) failed. First error: \(error.localizedDescription)"
            }
            return "Batch operation failed: \(count) item(s) failed"
        }
    }
}

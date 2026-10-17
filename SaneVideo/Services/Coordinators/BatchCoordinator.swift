import Foundation

struct BatchItemResult<T: Sendable>: @unchecked Sendable {
    let item: T
    let success: Bool
    let error: Error?
}

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

enum BatchCoordinator {

    /// - Parameters:
    ///   - config: Batch configuration (default: 4 concurrent workers)
    ///   - progressHandler: Optional progress callback (current index, total count)
    static func execute<T: Sendable>(
        items: [T],
        config: BatchConfig = .default,
        operation: @escaping @Sendable (T, Int) async throws -> Void,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [BatchItemResult<T>] {
        guard !items.isEmpty else { return [] }

        let total = items.count
        var results: [BatchItemResult<T>?] = Array(repeating: nil, count: total)
        var completedCount = 0
        var lastProgressUpdate = Date()

        await withTaskGroup(of: (Int, Result<Void, Error>).self) { group in
            var activeTasks = 0

            for (index, item) in items.enumerated() {
                if activeTasks >= config.maxConcurrent {
                    let (completedIndex, result) = await group.next()!
                    activeTasks -= 1
                    completedCount += 1

                    switch result {
                    case .success:
                        results[completedIndex] = BatchItemResult(item: items[completedIndex], success: true, error: nil)
                    case .failure(let error):
                        results[completedIndex] = BatchItemResult(item: items[completedIndex], success: false, error: error)
                    }

                    let now = Date()
                    if now.timeIntervalSince(lastProgressUpdate) >= config.progressUpdateInterval {
                        progressHandler?(completedCount, total)
                        lastProgressUpdate = now
                    }
                }

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

            while activeTasks > 0 {
                let (completedIndex, result) = await group.next()!
                activeTasks -= 1
                completedCount += 1

                switch result {
                case .success:
                    results[completedIndex] = BatchItemResult(item: items[completedIndex], success: true, error: nil)
                case .failure(let error):
                    results[completedIndex] = BatchItemResult(item: items[completedIndex], success: false, error: error)
                }

                let now = Date()
                if now.timeIntervalSince(lastProgressUpdate) >= config.progressUpdateInterval {
                    progressHandler?(completedCount, total)
                    lastProgressUpdate = now
                }
            }
        }

        progressHandler?(total, total)

        return results.compactMap { $0 }
    }

    /// Execute batch operation with simplified API (throws on failure)
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

        if !config.continueOnError {
            let failures = results.filter { !$0.success }
            if !failures.isEmpty {
                throw BatchError.operationFailed(failures.count, failures.first?.error)
            }
        }
    }
}

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

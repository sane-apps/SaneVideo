import Foundation

/// A wrapper to forcefully pass non-Sendable types across concurrency boundaries.
/// Use with extreme caution.
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    
    init(_ value: T) {
        self.value = value
    }
}

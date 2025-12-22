import Foundation

/// A wrapper to forcefully pass non-Sendable types across concurrency boundaries
/// Use with extreme caution and only when you know the value is effectively thread-safe
/// or ownership is being transferred safely.
struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    
    init(_ value: T) {
        self.value = value
    }
}

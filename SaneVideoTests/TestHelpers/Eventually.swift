import Foundation

/// Polls `condition` until it holds or `timeout` passes, and returns the last result.
/// Use it to wait for work the app starts in an unstructured Task, instead of a fixed sleep.
@MainActor
func eventually(
    timeout: Duration = .seconds(5),
    _ condition: () async -> Bool
) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() {
            return true
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

import Foundation

public struct CursorSample: Codable, Sendable, Equatable {
    /// Time relative to recording start (seconds)
    public let timestamp: TimeInterval

    /// Normalized X position (0-1, left to right)
    public let x: Double

    /// Normalized Y position (0-1, top to bottom)
    public let y: Double

    public let isDown: Bool

    /// Mouse button state (0 = none/left, 1 = right, 2 = middle)
    public let button: Int

    public init(
        timestamp: TimeInterval,
        x: Double,
        y: Double,
        isDown: Bool = false,
        button: Int = 0
    ) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.isDown = isDown
        self.button = button
    }

    var position: (x: Double, y: Double) {
        (x, y)
    }
}

//
//  CursorSample.swift
//  SaneVideo
//
//  Model for continuous cursor position tracking during recording.
//  Extends click-only tracking with full mouse movement data.
//

import Foundation

/// A single cursor position sample captured during recording
public struct CursorSample: Codable, Sendable, Equatable {
    /// Time relative to recording start (seconds)
    public let timestamp: TimeInterval

    /// Normalized X position (0-1, left to right)
    public let x: Double

    /// Normalized Y position (0-1, top to bottom)
    public let y: Double

    /// Whether a mouse button is held down at this sample
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

    /// Normalized position as a tuple
    var position: (x: Double, y: Double) {
        (x, y)
    }
}

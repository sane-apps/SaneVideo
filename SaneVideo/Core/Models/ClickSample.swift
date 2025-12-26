//
//  ClickSample.swift
//  SaneVideo
//
//  Model for storing mouse click events during recording
//  Used for auto-zoom feature (Screen Studio style)
//

import Foundation

/// Struct to store a single mouse click event
public struct ClickSample: Codable, Sendable, Equatable {
    public let timestamp: TimeInterval // Relative to recording start
    public let x: Double // Normalized 0-1 (Screen coordinates)
    public let y: Double // Normalized 0-1
    public let button: Int // 0 = left, 1 = right, 2 = middle

    public init(timestamp: TimeInterval, x: Double, y: Double, button: Int = 0) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.button = button
    }
}

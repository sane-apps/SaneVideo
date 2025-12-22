//
//  CursorSample.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation

/// Struct to store a single cursor position sample
public struct CursorSample: Codable, Sendable, Equatable {
    public let timestamp: TimeInterval // Relative to recording start
    public let x: Double // Normalized 0-1 (Screen coordinates)
    public let y: Double // Normalized 0-1

    public init(timestamp: TimeInterval, x: Double, y: Double) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
    }
}

//
//  KeystrokeSample.swift
//  SaneVideo
//
//  Captures keyboard shortcuts and navigation keys locally for demo overlays.
//

import Foundation

public struct KeystrokeSample: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let timestamp: TimeInterval
    public let key: String
    public let modifiers: [String]
    public let keyCode: UInt16

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        key: String,
        modifiers: [String] = [],
        keyCode: UInt16
    ) {
        self.id = id
        self.timestamp = timestamp
        self.key = key
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public var displayText: String {
        let parts = modifiers + [key]
        return parts.joined(separator: " + ")
    }
}

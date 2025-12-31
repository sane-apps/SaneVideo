//  RecordingModels.swift
//  SaneVideo
//
//  Enums and value types for recording and export

import AVFoundation
import Foundation

// MARK: - Recording Source

/// Recording source for video capture
/// Sendable for safe cross-actor usage
enum RecordingSource: Sendable, Equatable {
    case camera
    case screen

    // Force nonisolated conformance to suppress false positive Actor Isolation errors
    nonisolated static func == (lhs: RecordingSource, rhs: RecordingSource) -> Bool {
        switch (lhs, rhs) {
        case (.camera, .camera): return true
        case (.screen, .screen): return true
        default: return false
        }
    }
}

// VideoFilter removed
// RecordingMode removed - use AppState.appMode instead

// MARK: - Export Settings

/// Settings for video export
/// Settings for video export
public struct SaneExportSettings: Codable, Sendable {
    var codec: AVVideoCodecType = .hevc
    var resolution: ExportResolution = .uhd4K
    var bitrate: Int = 20_000_000 // 20 Mbps for 4K
    var frameRate: Float = 60.0

    public enum ExportResolution: String, Codable, Sendable {
        case hd720 = "720p"
        case hd1080 = "1080p"
        case uhd4K = "4K"

        public var size: CGSize {
            switch self {
            case .hd720: CGSize(width: 1280, height: 720)
            case .hd1080: CGSize(width: 1920, height: 1080)
            case .uhd4K: CGSize(width: 3840, height: 2160)
            }
        }

        public var displayName: String { rawValue }
    }

    // Custom Codable to handle AVVideoCodecType
    enum CodingKeys: String, CodingKey {
        case codec, resolution, bitrate, frameRate
    }

    public init(codec: AVVideoCodecType = .hevc, resolution: ExportResolution = .uhd4K, bitrate: Int = 20_000_000, frameRate: Float = 60.0) {
        self.codec = codec
        self.resolution = resolution
        self.bitrate = bitrate
        self.frameRate = frameRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let codecString = try container.decode(String.self, forKey: .codec)
        codec = AVVideoCodecType(rawValue: codecString)
        resolution = try container.decode(ExportResolution.self, forKey: .resolution)
        bitrate = try container.decode(Int.self, forKey: .bitrate)
        frameRate = try container.decode(Float.self, forKey: .frameRate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(codec.rawValue, forKey: .codec)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(bitrate, forKey: .bitrate)
        try container.encode(frameRate, forKey: .frameRate)
    }

    /// File extension for export based on codec
    /// HEVC with Alpha requires MOV container; others use MP4
    var fileExtension: String {
        codec == .hevcWithAlpha ? "mov" : "mp4"
    }
}

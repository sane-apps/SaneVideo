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
public struct SaneExportSettings: Codable, Sendable {
    var codec: AVVideoCodecType = .hevc
    var resolution: ExportResolution = .uhd4K
    var bitrate: Int = 20_000_000 // 20 Mbps for 4K
    var frameRate: Float = 60.0

    /// Target aspect ratio for export (nil = use source aspect ratio)
    /// Used by vertical platform presets (TikTok, Reels, Shorts)
    var aspectRatio: ShortAspectRatio?

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
        case codec, resolution, bitrate, frameRate, aspectRatio
    }

    public init(
        codec: AVVideoCodecType = .hevc,
        resolution: ExportResolution = .uhd4K,
        bitrate: Int = 20_000_000,
        frameRate: Float = 60.0,
        aspectRatio: ShortAspectRatio? = nil
    ) {
        self.codec = codec
        self.resolution = resolution
        self.bitrate = bitrate
        self.frameRate = frameRate
        self.aspectRatio = aspectRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let codecString = try container.decode(String.self, forKey: .codec)
        codec = AVVideoCodecType(rawValue: codecString)
        resolution = try container.decode(ExportResolution.self, forKey: .resolution)
        bitrate = try container.decode(Int.self, forKey: .bitrate)
        frameRate = try container.decode(Float.self, forKey: .frameRate)
        aspectRatio = try container.decodeIfPresent(ShortAspectRatio.self, forKey: .aspectRatio)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(codec.rawValue, forKey: .codec)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(bitrate, forKey: .bitrate)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
    }

    /// Computed render size based on resolution and aspect ratio
    /// For vertical formats (9:16), swaps width/height
    /// For square (1:1), uses height for both dimensions
    var renderSize: CGSize {
        guard let aspect = aspectRatio else {
            // No aspect ratio override - use standard resolution size
            return resolution.size
        }

        let baseHeight = resolution.size.height
        switch aspect {
        case .vertical9x16:
            // Vertical: width = height × (9/16), then swap
            // For 1080p: 1080×1920
            // For 4K: 2160×3840
            let width = baseHeight * (9.0 / 16.0)
            return CGSize(width: width, height: baseHeight * (16.0 / 9.0))
        case .square1x1:
            // Square: use height for both
            return CGSize(width: baseHeight, height: baseHeight)
        case .portrait4x5:
            // Portrait: width = height × (4/5)
            let width = baseHeight * (4.0 / 5.0)
            return CGSize(width: width, height: baseHeight)
        }
    }

    /// File extension for export based on codec
    /// HEVC with Alpha requires MOV container; others use MP4
    var fileExtension: String {
        codec == .hevcWithAlpha ? "mov" : "mp4"
    }
}

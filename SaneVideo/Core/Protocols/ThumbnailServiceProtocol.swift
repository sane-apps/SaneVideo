//
//  ThumbnailServiceProtocol.swift
//  SaneVideo
//
//  Protocol for thumbnail generation and caching
//

@preconcurrency import AppKit
@preconcurrency import AVFoundation
import Foundation

/// @mockable
protocol ThumbnailServiceProtocol: Actor {
    /// Request a thumbnail for a specific time
    func thumbnail(for clip: VideoClip, time: CMTime, size: CGSize) async -> UncheckedBox<NSImage>?

    /// Clear the thumbnail cache
    func clearCache()

    /// Generates the "best" thumbnail from the video by analyzing frames
    func generateBestThumbnail(for url: URL, strategy: ThumbnailScoringStrategy) async throws -> UncheckedBox<NSImage>

    /// Generates a smart thumbnail and saves it to disk
    func generateSmartThumbnail(for url: URL, strategy: ThumbnailScoringStrategy) async throws -> URL
}

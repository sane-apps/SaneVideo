//
//  ThumbnailFrameLoader.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

@preconcurrency import AppKit
@preconcurrency import AVFoundation
import Vision

/// Handles loading and scoring thumbnail frame candidates from video
enum ThumbnailFrameLoader {
    
    /// Load candidate frames from video with face detection scoring
    static func loadCandidates(from videoURL: URL) async throws -> (candidates: [ThumbnailCandidate], duration: Double) {
        let asset = AVURLAsset(url: videoURL)
        let assetDuration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(assetDuration)
        
        let sampleTimes: [(Double, String)] = [
            (0.15, "Opening"),
            (0.35, "Early"),
            (0.5, "Middle"),
            (0.65, "Late"),
            (0.85, "Ending")
        ]
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        var loadedCandidates: [ThumbnailCandidate] = []
        
        for (fraction, label) in sampleTimes {
            let time = CMTime(seconds: durationSeconds * fraction, preferredTimescale: 600)
            
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                let score = try calculateScore(for: cgImage)
                
                loadedCandidates.append(ThumbnailCandidate(
                    image: nsImage, label: label, score: score, time: time
                ))
            } catch { }
        }
        
        // Sort by score descending (best first)
        loadedCandidates.sort { $0.score > $1.score }
        
        return (loadedCandidates, durationSeconds)
    }
    
    /// Get a frame at a specific time
    static func getFrame(from videoURL: URL, at time: Double) async throws -> UncheckedBox<NSImage> {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: cmTime)
        return UncheckedBox(
            NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        )
    }
    
    /// Calculate a "quality score" for a frame based on face detection
    private static func calculateScore(for cgImage: CGImage) throws -> Float {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let results = request.results else { return 0.0 }
        return results.reduce(0) { $0 + Float($1.boundingBox.width * $1.boundingBox.height) }
    }
}

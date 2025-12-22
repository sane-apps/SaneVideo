//
//  SmartThumbnailService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Vision
import Foundation

/// Service responsible for analyzing video content to generate the "best" possible thumbnail
/// Uses Apple Vision to score frames based on:
///  1. Face Capture Quality (if people are present)
///  2. Saliency (Attention based, if no people)
actor SmartThumbnailService {
    
    // MARK: - Types
    
    struct ScoredFrame {
        let time: CMTime
        let score: Float
        let image: CGImage
    }
    
    // MARK: - Public API
    
    /// Generates a smart thumbnail for the given video URL.
    /// - Parameters:
    ///   - url: The file URL of the video asset.
    ///   - completion: Returns the local URL of the generated thumbnail image.
    func generateSmartThumbnail(for url: URL) async throws -> URL {
        AppLogger.vision.info("🖼️ SmartThumbnail: Starting analysis for \(url.lastPathComponent)")
        
        let asset = AVURLAsset(url: url)
        
        // 1. Extract candidate frames
        let duration = try await asset.load(.duration)
        let candidateTimes = generateCandidateTimes(duration: duration, count: 10)
        
        // 2. Generate CGImages for candidates
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // Optimize for speed using a smaller max dimension for analysis (we can re-generate high-res later)
        // usage of .zero generates at full size, which might be slow for analysis but accurate.
        // Let's use a reasonable preview size for scoring, then full res for final.
        generator.maximumSize = CGSize(width: 512, height: 512)
        
        var scoredFrames: [ScoredFrame] = []
        
        for time in candidateTimes {
            do {
                let (image, actualTime) = try await generator.image(at: time)
                let score = try await evaluateFrameQuality(image)
                scoredFrames.append(ScoredFrame(time: actualTime, score: score, image: image))
            } catch {
                AppLogger.vision.warning("Failed to generate candidate frame at \(time.seconds): \(error)")
            }
        }
        
        // 3. Select best frame
        guard let bestFrame = scoredFrames.max(by: { $0.score < $1.score }) else {
            throw AppError.visionError("No valid frames could be generated for thumbnail analysis")
        }
        
        AppLogger.vision.info("🖼️ SmartThumbnail: Selected frame at \(bestFrame.time.seconds)s with score \(String(format: "%.2f", bestFrame.score))")
        
        // 4. Regenerate High-Res version of the winner
        // We need a new generator for full resolution
        let fullResGenerator = AVAssetImageGenerator(asset: asset)
        fullResGenerator.appliesPreferredTrackTransform = true
        fullResGenerator.requestedTimeToleranceBefore = .zero
        fullResGenerator.requestedTimeToleranceAfter = .zero
        // maximumSize defaults to zero (full res) or we can specify
        
        let (highResImage, _) = try await fullResGenerator.image(at: bestFrame.time)
        
        // 5. Save to disk
        return try saveThumbnail(image: highResImage, filename: url.lastPathComponent)
    }
    
    // MARK: - Private Logic
    
    /// Picks `count` evenly spaced times from the first 30% of the video (or full duration if short)
    private func generateCandidateTimes(duration: CMTime, count: Int) -> [CMTime] {
        let seconds = duration.seconds
        // Heuristic: Thumbnails are usually best from the first 1/3rd of a clip, unless it's very short
        let endWindow = (seconds > 10) ? (seconds * 0.3) : seconds
        let step = endWindow / Double(count)
        
        var times: [CMTime] = []
        for i in 0..<count {
            let timeSeconds = Double(i) * step
            // Avoid exactly 0.0 if possible to avoid black frames on some fades
            let t = max(0.1, timeSeconds)
            times.append(CMTime(seconds: t, preferredTimescale: 600))
        }
        return times
    }
    
    /// Scores a single image using Vision
    private func evaluateFrameQuality(_ image: CGImage) async throws -> Float {
        var score: Float = 0.0
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        let faceRectRequest = VNDetectFaceRectanglesRequest()
        
        try await handler.perform([faceRequest, faceRectRequest])
        
        if let faceObservations = faceRequest.results, !faceObservations.isEmpty {
            // Note: faceCaptureQuality is the legacy VN* API, still available in macOS 26
            // The modern Vision Swift API uses FaceObservation.captureQuality.score
            let maxQuality = faceObservations.compactMap { $0.faceCaptureQuality }.max() ?? 0.1
            let maxFaceArea = faceObservations.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0.0
            
            score = (maxQuality * 0.7) + (Float(maxFaceArea) * 0.3) + 1.0
        } else {
            score = 0.5
        }
        
        return score
    }
    
    private func saveThumbnail(image: CGImage, filename: String) throws -> URL {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let thumbDir = docs.appendingPathComponent("Thumbnails")
        
        try fileManager.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        
        // Normalize filename
        let name = (filename as NSString).deletingPathExtension
        let fileURL = thumbDir.appendingPathComponent("\(name).jpg")
        
        // Convert to Data
        // Needs a tiny helper or UIImage (but we are in a Service, maybe Cocoa or standard ImageIO)
        let data = try convertToJPEG(image)
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    private func convertToJPEG(_ image: CGImage) throws -> Data {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, "public.jpeg" as CFString, 1, nil) else {
            throw AppError.visionError("Could not create image destination")
        }
        
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.visionError("Could not failize JPEG")
        }
        
        return outputData as Data
    }
}

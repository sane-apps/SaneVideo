//
//  TextRecognitionService.swift
//  SaneVideo
//
//  Apple Vision framework for text recognition (OCR)
//  Detects and extracts text from video frames
//

import AVFoundation
import CoreImage
import Foundation
import Vision

/// Recognized text region in a frame
struct RecognizedText: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect // Normalized 0-1
    let confidence: Float
    let time: CMTime
}

/// Types of text that can be detected
enum TextType: Sendable {
    case any
    case email
    case phone
    case url
    case address

    var dataDetectorType: NSTextCheckingResult.CheckingType? {
        switch self {
        case .any: return nil
        case .email: return .link
        case .phone: return .phoneNumber
        case .url: return .link
        case .address: return .address
        }
    }
}

/// Service for detecting and recognizing text in video frames
actor TextRecognitionService {

    init() {}

    /// Recognize all text in an image
    func recognizeText(in image: CIImage, at time: CMTime = .zero) async throws -> [RecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        return observations.compactMap { observation -> RecognizedText? in
            guard let topCandidate = observation.topCandidates(1).first else {
                return nil
            }

            let box = observation.boundingBox
            return RecognizedText(
                text: topCandidate.string,
                boundingBox: CGRect(
                    x: box.minX,
                    y: 1.0 - box.maxY, // Flip Y
                    width: box.width,
                    height: box.height
                ),
                confidence: topCandidate.confidence,
                time: time
            )
        }
    }

    /// Find sensitive text (emails, phones, etc.) for auto-blur
    func findSensitiveText(
        in image: CIImage,
        types: [TextType] = [.email, .phone],
        at time: CMTime = .zero
    ) async throws -> [RecognizedText] {
        let allText = try await recognizeText(in: image, at: time)

        return allText.filter { recognized in
            let text = recognized.text

            for type in types {
                switch type {
                case .email:
                    if text.contains("@"), text.contains(".") {
                        return true
                    }
                case .phone:
                    let digits = text.filter { $0.isNumber }
                    if digits.count >= 7 {
                        return true
                    }
                case .url:
                    if text.contains("http") || text.contains("www.") {
                        return true
                    }
                case .address:
                    // Simple heuristic
                    if text.contains("Street") || text.contains("Ave") || text.contains("Blvd") {
                        return true
                    }
                case .any:
                    return true
                }
            }
            return false
        }
    }

    /// Scan video for all text occurrences
    /// - Parameters:
    ///   - videoURL: URL of video to scan
    ///   - sampleInterval: Seconds between frame samples
    ///   - progressHandler: Optional callback with (currentFrame, totalFrames)
    func scanVideoForText(
        videoURL: URL,
        sampleInterval: TimeInterval = 2.0,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [RecognizedText] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalFrames = Int(duration.seconds / sampleInterval)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        var allText: [RecognizedText] = []
        var currentTime = CMTime.zero
        var frameIndex = 0

        await MainActor.run {
            AppLogger.vision.info("📝 Scanning \(totalFrames) frames for text (OCR)...")
        }

        var skippedFrames = 0

        while currentTime < duration {
            frameIndex += 1
            progressHandler?(frameIndex, totalFrames)

            do {
                let (cgImage, actualTime) = try await generator.image(at: currentTime)
                let ciImage = CIImage(cgImage: cgImage)
                let textInFrame = try await recognizeText(in: ciImage, at: actualTime)
                allText.append(contentsOf: textInFrame)
            } catch {
                // Track skipped frames instead of silently ignoring
                skippedFrames += 1
            }

            currentTime = currentTime + CMTime(seconds: sampleInterval, preferredTimescale: 600)
        }

        // Log summary if frames were skipped
        if skippedFrames > 0 {
            let skipped = skippedFrames
            await MainActor.run {
                AppLogger.vision.warning("📝 Text recognition: Skipped \(skipped)/\(totalFrames) frames due to errors")
            }
        }

        // Deduplicate similar text
        return deduplicateText(allText)
    }

    /// Search video for specific text
    func searchVideo(
        videoURL: URL,
        query: String,
        caseSensitive: Bool = false
    ) async throws -> [RecognizedText] {
        let allText = try await scanVideoForText(videoURL: videoURL)

        let searchQuery = caseSensitive ? query : query.lowercased()

        return allText.filter { recognized in
            let text = caseSensitive ? recognized.text : recognized.text.lowercased()
            return text.contains(searchQuery)
        }
    }

    // MARK: - Private

    private func deduplicateText(_ texts: [RecognizedText]) -> [RecognizedText] {
        var seen: Set<String> = []
        var unique: [RecognizedText] = []

        for text in texts {
            let normalized = text.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                unique.append(text)
            }
        }

        return unique
    }
}

/// Extension to generate blur regions for detected text
extension TextRecognitionService {
    /// Get regions to blur for privacy protection
    func getBlurRegions(
        in image: CIImage,
        blurSensitive: Bool = true,
        at time: CMTime = .zero
    ) async throws -> [CGRect] {
        if blurSensitive {
            let sensitive = try await findSensitiveText(in: image, at: time)
            return sensitive.map { $0.boundingBox }
        } else {
            let allText = try await recognizeText(in: image, at: time)
            return allText.map { $0.boundingBox }
        }
    }
}

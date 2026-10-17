@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import SoundAnalysis

enum RepurposingPhase: String, Sendable {
    case loading = "Loading video..."
    case analyzingAudio = "Analyzing audio..."
    case detectingHighlights = "Detecting highlights..."
    case detectingFaces = "Detecting faces..."
    case analyzingSaliency = "Finding key moments..."
    case scoringCandidates = "Scoring candidates..."
    case complete = "Complete"
}

typealias RepurposingProgressHandler = @Sendable (RepurposingPhase, Double) -> Void

private enum AnalysisResult: Sendable {
    case silence([CMTimeRange])
    case highlights([(CMTimeRange, HighlightType)])
    case saliency([CMTime: SaliencyResult])
}

/// Actor for orchestrating long-to-short video repurposing
actor RepurposingOrchestrator {

    // MARK: - Dependencies

    private let saliencyService: SaliencyService
    private let silenceDetector: SilenceDetector
    private let soundAnalysisService: SoundAnalysisService

    // MARK: - Configuration

    /// Minimum segment length to consider (seconds)
    private let minSegmentLength: Double = 10.0

    /// Maximum overlapping segments when building candidates
    private let maxOverlap: Double = 5.0

    private struct SegmentAnalysisData {
        let speakingRanges: [CMTimeRange]
        let audioHighlights: [(CMTimeRange, HighlightType)]
        let saliencyData: [CMTime: SaliencyResult]
        let captions: [Caption]
    }

    init(
        saliencyService: SaliencyService,
        silenceDetector: SilenceDetector,
        soundAnalysisService: SoundAnalysisService
    ) {
        self.saliencyService = saliencyService
        self.silenceDetector = silenceDetector
        self.soundAnalysisService = soundAnalysisService
    }

    /// Convenience initializer using ServiceContainer (must be called from MainActor)
    @MainActor
    init() {
        self.saliencyService = ServiceContainer.shared.saliencyService
        self.silenceDetector = ServiceContainer.shared.silenceDetector
        self.soundAnalysisService = ServiceContainer.shared.soundAnalysisService
    }

    // MARK: - Main Analysis

    func analyzeForShorts(
        videoURL: URL,
        captions: [Caption] = [],
        settings: RepurposingSettings,
        progressHandler: RepurposingProgressHandler? = nil
    ) async throws -> [ShortCandidate] {

        progressHandler?(.loading, 0.0)
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = duration.seconds

        guard totalSeconds > Double(settings.targetDuration.rawValue) else {
            throw RepurposingError.videoTooShort(
                duration: totalSeconds,
                required: Double(settings.targetDuration.rawValue)
            )
        }

        // Audio and vision analysis are independent, so run them in parallel.
        progressHandler?(.analyzingAudio, 0.1)

        var silenceRanges: [CMTimeRange] = []
        var audioHighlights: [(CMTimeRange, HighlightType)] = []
        var saliencyData: [CMTime: SaliencyResult] = [:]

        try await withThrowingTaskGroup(of: AnalysisResult.self) { group in
            group.addTask { [self] in
                let ranges = try await self.detectSilence(in: videoURL, duration: duration)
                return .silence(ranges)
            }

            group.addTask { [self] in
                let highlights = await self.detectAudioHighlights(in: videoURL)
                return .highlights(highlights)
            }

            group.addTask { [self] in
                let saliency = try await self.saliencyService.analyzeVideoForReframe(
                    videoURL: videoURL,
                    sampleInterval: 2.0
                )
                return .saliency(saliency)
            }

            for try await result in group {
                switch result {
                case .silence(let ranges):
                    silenceRanges = ranges
                    progressHandler?(.detectingHighlights, 0.3)
                case .highlights(let highlights):
                    audioHighlights = highlights
                    progressHandler?(.detectingFaces, 0.5)
                case .saliency(let saliency):
                    saliencyData = saliency
                    progressHandler?(.scoringCandidates, 0.6)
                }
            }
        }

        // Compute speaking ranges from silence (must happen after silence detection)
        let speakingRanges = invertRanges(silenceRanges, duration: duration)

        progressHandler?(.scoringCandidates, 0.7)
        let targetDuration = Double(settings.targetDuration.rawValue)
        let analysisData = SegmentAnalysisData(
            speakingRanges: speakingRanges,
            audioHighlights: audioHighlights,
            saliencyData: saliencyData,
            captions: captions
        )
        var candidates = buildCandidateSegments(
            analysisData: analysisData,
            targetDuration: targetDuration,
            totalDuration: totalSeconds
        )

        progressHandler?(.scoringCandidates, 0.9)
        candidates = scoreCandidates(
            candidates,
            silenceRanges: silenceRanges,
            audioHighlights: audioHighlights,
            saliencyData: saliencyData,
            settings: settings
        )

        // Pick top candidates without overlap.
        let selectedCandidates = selectBestCandidates(
            from: candidates,
            maxCount: settings.maxShorts,
            minGap: 5.0  // At least 5 seconds between shorts
        )

        progressHandler?(.complete, 1.0)

        return selectedCandidates
    }

    // MARK: - Audio Analysis

    private func detectSilence(
        in url: URL,
        duration: CMTime
    ) async throws -> [CMTimeRange] {
        let asset = AVURLAsset(url: url)

        let config = SilenceDetector.Configuration(
            dbThreshold: -35.0,
            minDuration: 0.5
        )

        return try await silenceDetector.detectSilenceInAsset(
            asset: asset,
            config: config
        )
    }

    private func detectAudioHighlights(in url: URL) async -> [(CMTimeRange, HighlightType)] {
        // Use SoundAnalysis to find applause, laughter, etc.
        do {
            let classifications = try await analyzeAudioFile(url: url)
            return classifications.compactMap { classification -> (CMTimeRange, HighlightType)? in
                switch classification.label {
                case .applause:
                    return (classification.timeRange, .applause)
                case .laughter:
                    return (classification.timeRange, .laughter)
                case .music where classification.confidence > 0.7:
                    return (classification.timeRange, .musicPeak)
                default:
                    return nil
                }
            }
        } catch {
            AppLogger.general.warning("Audio highlight detection failed: \(error.localizedDescription)")
            return []
        }
    }

    private func analyzeAudioFile(url: URL) async throws -> [AudioClassification] {
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)

        let observer = FileAnalysisObserver()
        try analyzer.add(request, withObserver: observer)

        _ = await analyzer.analyze()

        return observer.results
    }

    // MARK: - Segment Building

    private func buildCandidateSegments(
        analysisData: SegmentAnalysisData,
        targetDuration: Double,
        totalDuration: Double
    ) -> [ShortCandidate] {

        var candidates: [ShortCandidate] = []
        let stepSize = targetDuration / 2  // 50% overlap between potential segments

        var currentStart = 0.0
        while currentStart + targetDuration <= totalDuration {
            let startTime = CMTime(seconds: currentStart, preferredTimescale: 600)
            let candidateDuration = CMTime(seconds: targetDuration, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: candidateDuration)

            let segmentHighlights = analysisData.audioHighlights
                .filter { timeRange.containsTimeRange($0.0) || $0.0.intersection(timeRange).duration.seconds > 0 }
                .map { $0.1 }

            let hasFace = analysisData.saliencyData.contains { time, result in
                timeRange.containsTime(time) && result.confidence > 0.6
            }

            let relevantSaliency = analysisData.saliencyData.filter { timeRange.containsTime($0.key) }
            let avgSaliency = relevantSaliency.isEmpty ? 0.5 :
                relevantSaliency.values.map { Double($0.confidence) }.reduce(0, +) / Double(relevantSaliency.count)

            let hasCaption = analysisData.captions.contains { caption in
                let captionStart = caption.startTime.seconds
                let captionEnd = caption.endTime.seconds
                return captionStart >= currentStart && captionEnd <= currentStart + targetDuration
            }

            let suggestedCrop: SuggestedCrop
            if let bestSaliency = relevantSaliency.values.max(by: { $0.confidence < $1.confidence }) {
                suggestedCrop = SuggestedCrop(
                    centerX: bestSaliency.attentionPoint.x,
                    centerY: bestSaliency.attentionPoint.y,
                    scale: 1.2
                )
            } else {
                suggestedCrop = .default
            }

            let candidate = ShortCandidate(
                timeRange: timeRange,
                score: avgSaliency,  // Initial score, will be refined
                suggestedCrop: suggestedCrop,
                highlights: Array(Set(segmentHighlights)),
                hasFace: hasFace,
                silencePercentage: 0.0,  // Will be calculated in scoring
                averageLoudness: 0.0,
                hasCaption: hasCaption
            )

            candidates.append(candidate)
            currentStart += stepSize
        }

        return candidates
    }

    // MARK: - Scoring

    private func scoreCandidates(
        _ candidates: [ShortCandidate],
        silenceRanges: [CMTimeRange],
        audioHighlights: [(CMTimeRange, HighlightType)],
        saliencyData: [CMTime: SaliencyResult],
        settings: RepurposingSettings
    ) -> [ShortCandidate] {

        return candidates.map { candidate in
            var scored = candidate

            let silenceInSegment = silenceRanges
                .map { $0.intersection(candidate.timeRange) }
                .filter { $0.duration.seconds > 0 }
                .reduce(0.0) { $0 + $1.duration.seconds }
            let silencePercentage = silenceInSegment / candidate.duration

            scored.silencePercentage = silencePercentage

            // Weights: highlight=0.3, face=0.2, noSilence=0.2, caption=0.2, saliency=0.1
            var score = 0.0

            if !candidate.highlights.isEmpty {
                score += 0.3 * min(Double(candidate.highlights.count) / 3.0, 1.0)
            }

            if candidate.hasFace {
                score += 0.2
            }

            if silencePercentage < 0.2 {
                score += 0.2 * (1.0 - silencePercentage * 5)
            }

            if candidate.hasCaption {
                score += 0.2
            }

            let relevantSaliency = saliencyData.filter { candidate.timeRange.containsTime($0.key) }
            if !relevantSaliency.isEmpty {
                let avgConfidence = relevantSaliency.values.map { Double($0.confidence) }.reduce(0, +)
                    / Double(relevantSaliency.count)
                score += 0.1 * avgConfidence
            }

            scored.score = min(max(score, 0.0), 1.0)
            scored.silencePercentage = silencePercentage

            return scored
        }
    }

    // MARK: - Selection

    private func selectBestCandidates(
        from candidates: [ShortCandidate],
        maxCount: Int,
        minGap: Double
    ) -> [ShortCandidate] {

        let sorted = candidates.sorted { $0.score > $1.score }

        var selected: [ShortCandidate] = []

        for candidate in sorted {
            guard selected.count < maxCount else { break }

            let hasOverlap = selected.contains { existing in
                let gap = abs(candidate.startTime - existing.endTime)
                let gap2 = abs(existing.startTime - candidate.endTime)
                return min(gap, gap2) < minGap
            }

            if !hasOverlap {
                selected.append(candidate)
            }
        }

        return selected.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Utilities

    private func invertRanges(_ ranges: [CMTimeRange], duration: CMTime) -> [CMTimeRange] {
        var inverted: [CMTimeRange] = []
        var cursor = CMTime.zero

        let sorted = ranges.sorted { $0.start < $1.start }

        for range in sorted {
            if range.start > cursor {
                inverted.append(CMTimeRange(start: cursor, end: range.start))
            }
            cursor = max(cursor, range.end)
        }

        if cursor < duration {
            inverted.append(CMTimeRange(start: cursor, end: duration))
        }

        return inverted
    }
}

// MARK: - File Analysis Observer

private class FileAnalysisObserver: NSObject, SNResultsObserving {
    var results: [AudioClassification] = []

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }

        for classification in classificationResult.classifications where classification.confidence > 0.4 {
            let label = AudioLabel(rawValue: classification.identifier) ?? .unknown
            results.append(AudioClassification(
                timeRange: classificationResult.timeRange,
                label: label,
                confidence: Float(classification.confidence)
            ))
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        AppLogger.audio.error("File analysis failed: \(error.localizedDescription)")
    }
}

// MARK: - Errors

enum RepurposingError: LocalizedError {
    case videoTooShort(duration: Double, required: Double)
    case analysisFailureAudio(Error)
    case analysisFailureVideo(Error)
    case noCandidatesFound

    var errorDescription: String? {
        switch self {
        case .videoTooShort(let duration, let required):
            return "Video is too short (\(Int(duration))s). Minimum \(Int(required))s required."
        case .analysisFailureAudio(let error):
            return "Audio analysis failed: \(error.localizedDescription)"
        case .analysisFailureVideo(let error):
            return "Video analysis failed: \(error.localizedDescription)"
        case .noCandidatesFound:
            return "No suitable short clips found in the video."
        }
    }
}

// MARK: - SilenceDetector Extension

extension SilenceDetector {
    func detectSilenceInAsset(
        asset: AVAsset,
        config: Configuration
    ) async throws -> [CMTimeRange] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            return []  // No audio = no silence to detect
        }

        let duration = try await asset.load(.duration)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw SilenceDetectorError.readerFailed
        }

        var silentRanges: [CMTimeRange] = []
        var currentSilenceStart: CMTime?
        var currentTime = CMTime.zero

        let dbThreshold = config.dbThreshold
        let minDuration = config.minDuration

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )

            if let data = dataPointer {
                let floatCount = length / MemoryLayout<Float>.size
                let floats = data.withMemoryRebound(to: Float.self, capacity: floatCount) {
                    Array(UnsafeBufferPointer(start: $0, count: floatCount))
                }

                let sumOfSquares = floats.reduce(0) { $0 + $1 * $1 }
                let rms = sqrt(sumOfSquares / Float(floatCount))
                let db = 20 * log10(max(rms, 0.0001))

                let sampleDuration = CMSampleBufferGetDuration(sampleBuffer)

                if db < dbThreshold {
                    if currentSilenceStart == nil {
                        currentSilenceStart = currentTime
                    }
                } else {
                    if let start = currentSilenceStart {
                        let silenceDuration = (currentTime - start).seconds
                        if silenceDuration >= minDuration {
                            silentRanges.append(CMTimeRange(start: start, end: currentTime))
                        }
                        currentSilenceStart = nil
                    }
                }

                currentTime = currentTime + sampleDuration
            }
        }

        if let start = currentSilenceStart {
            let silenceDuration = (duration - start).seconds
            if silenceDuration >= minDuration {
                silentRanges.append(CMTimeRange(start: start, end: duration))
            }
        }

        return silentRanges
    }
}

private enum SilenceDetectorError: Error {
    case readerFailed
}

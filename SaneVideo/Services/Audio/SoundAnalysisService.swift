//
//  SoundAnalysisService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import SoundAnalysis

/// Service responsible for real-time audio analysis (sentiment, transcription)
@Observable
class SoundAnalysisService: @unchecked Sendable {
    
    // MARK: - Publishers
    var resultsStream = PassthroughSubject<AudioClassification, Never>()
    
    // MARK: - Private State
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var currentFormat: AVAudioFormat?
    private let analysisQueue = DispatchQueue(label: "com.sanevideo.soundAnalysis")
    
    // MARK: - Public Interface
    
    // Helper wrapper for strict concurrency
    struct SendableCMSampleBuffer: @unchecked Sendable {
        let buffer: CMSampleBuffer
    }

    func analyze(sampleBuffer: CMSampleBuffer) {
        let sendableBuffer = SendableCMSampleBuffer(buffer: sampleBuffer)
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            self.processBuffer(sendableBuffer.buffer)
        }
    }
    
    func startRealTimeAnalysis(format: AVAudioFormat) {
        // Stub for starting real-time analysis requests
        AppLogger.audio.info("SoundAnalysis: Real-time analysis started with format: \(format)")
        self.currentFormat = format
        self.streamAnalyzer = SNAudioStreamAnalyzer(format: format)
    }
    
    func stopRealTimeAnalysis() {
        AppLogger.audio.info("SoundAnalysis: Real-time analysis stopped")
        self.streamAnalyzer = nil
        self.currentFormat = nil
    }
    
    // MARK: - Internal Processing
    
    private func processBuffer(_ buffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(buffer) else { return }
        
        // 1. Convert CMFormat to AVAudioFormat
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        
        // 2. Check for format change or initialization
        if streamAnalyzer == nil || !areFormatsCompatible(format, currentFormat) {
            reinitializeAnalyzer(with: format)
        }
        
        // 3. Convert CMSampleBuffer to AVAudioPCMBuffer
        if let pcmBuffer = createPCMBuffer(from: buffer, format: format) {
            if let analyzer = streamAnalyzer {
                analyzer.analyze(pcmBuffer, atAudioFramePosition: -1)
            }
        }
    }

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        // Copy audio data from CMSampleBuffer to AVAudioPCMBuffer
        // For M1+, we assume standard Float32/Int16 formats
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        ) == kCMBlockBufferNoErr, let data = dataPointer else { return nil }

        // Simple copy for interleaved/non-interleaved based on format
        // Note: SoundAnalysis usually expects PCM data. 
        // We use pcmBuffer.floatChannelData or pcmBuffer.int16ChannelData
        if format.commonFormat == .pcmFormatFloat32 {
            for channel in 0..<Int(format.channelCount) {
                if let channelData = pcmBuffer.floatChannelData?[channel] {
                    let source = data.withMemoryRebound(to: Float.self, capacity: numSamples * Int(format.channelCount)) { $0 }
                    // If interleaved, we need to pick every Nth sample. If non-interleaved, it's easier.
                    // AVCaptureAudioDataOutput usually provides interleaved data.
                    for frame in 0..<numSamples {
                        channelData[frame] = source[frame * Int(format.channelCount) + channel]
                    }
                }
            }
        } else if format.commonFormat == .pcmFormatInt16 {
            for channel in 0..<Int(format.channelCount) {
                if let channelData = pcmBuffer.int16ChannelData?[channel] {
                    let source = data.withMemoryRebound(to: Int16.self, capacity: numSamples * Int(format.channelCount)) { $0 }
                    for frame in 0..<numSamples {
                        channelData[frame] = source[frame * Int(format.channelCount) + channel]
                    }
                }
            }
        }
        
        return pcmBuffer
    }
    
    private func areFormatsCompatible(_ newFormat: AVAudioFormat, _ currentFormat: AVAudioFormat?) -> Bool {
        guard let current = currentFormat else { return false }
        return newFormat.sampleRate == current.sampleRate &&
               newFormat.channelCount == current.channelCount
    }
    
    private func reinitializeAnalyzer(with format: AVAudioFormat) {
        AppLogger.audio.info("SoundAnalysis: Initializing/Re-initializing analyzer. Format: \(format)")
        
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        currentFormat = format
    }
    
    // MARK: - Semantic Gating
    
    struct GatingSegment: Sendable {
        let timeRange: CMTimeRange
        let shouldOpenGate: Bool
        let confidence: Float
    }
    
    /// Generates gating metadata for an audio file by analyzing speech presence
    func generateGatingMetadata(for url: URL) async throws -> [GatingSegment] {
        AppLogger.audio.info("SoundAnalysis: Generating gating metadata for \(url.lastPathComponent)")
        
        // 1. Setup Analyzer
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        
        let resultsObserver = GatingResultsObserver()
        try analyzer.add(request, withObserver: resultsObserver)
        
        // 2. Perform Analysis
        _ = await analyzer.analyze()
        
        // 3. Process Results
        let classifications = resultsObserver.results
        var segments: [GatingSegment] = []
        
        // Convert raw classifications to gating segments
        // We open the gate if 'speech' is the top classification with high enough confidence
        for result in classifications {
            let isSpeech = result.classifications.first { $0.identifier == "speech" }
            let confidence = isSpeech?.confidence ?? 0.0
            
            segments.append(GatingSegment(
                timeRange: result.timeRange,
                shouldOpenGate: confidence > 0.5,
                confidence: Float(confidence)
            ))
        }
        
        AppLogger.audio.info("SoundAnalysis: Generated \(segments.count) gating segments")
        return segments
    }
    
    // MARK: - File Analysis (Stubs for AudioSection)
    
    func findHighlights(in url: URL) async throws -> [AudioClassification] {
        // Validation stub
        return []
    }
    
    func analyzeAudio(in url: URL) async throws -> [AudioClassification] {
        // Validation stub
        return []
    }
}

// MARK: - Gating Observer

private class GatingResultsObserver: NSObject, SNResultsObserving {
    var results: [SNClassificationResult] = []
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        results.append(classificationResult)
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        AppLogger.audio.error("SoundAnalysis: Gating analysis failed: \(error.localizedDescription)")
    }
}

// MARK: - Supporting Types

struct AudioClassification {
    let timeRange: CMTimeRange
    let label: AudioLabel
    let confidence: Float
}

enum AudioLabel: String, Hashable {
    case speech, music, noise, applause, laughter, unknown
    
    var displayName: String {
        return rawValue.capitalized
    }
}

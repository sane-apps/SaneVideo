import AVFoundation
import Combine
import SoundAnalysis

@Observable
class SoundAnalysisService: @unchecked Sendable, SoundAnalysisServiceProtocol {

  // MARK: - Publishers
  var resultsStream = PassthroughSubject<AudioClassification, Never>()

  var onSoundDetected: ((AudioClassification) -> Void)?

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
    AppLogger.audio.info("SoundAnalysis: Real-time analysis started with format: \(format)")

    // All streamAnalyzer/currentFormat access stays on analysisQueue to avoid races with processBuffer.
    analysisQueue.sync { [self] in
      self.currentFormat = format
      self.streamAnalyzer = SNAudioStreamAnalyzer(format: format)

      do {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48000)
        request.overlapFactor = 0.5

        let observer = RealTimeResultsObserver { [weak self] classification in
          self?.onSoundDetected?(classification)
        }

        try streamAnalyzer?.add(request, withObserver: observer)
        AppLogger.audio.info("✅ SoundAnalysis: Request added successfully")

      } catch {
        AppLogger.audio.error("❌ SoundAnalysis: Failed to create request: \(error)")
      }
    }
  }

  func stopRealTimeAnalysis() {
    AppLogger.audio.info("SoundAnalysis: Real-time analysis stopped")
    analysisQueue.sync { [self] in
      self.streamAnalyzer = nil
      self.currentFormat = nil
    }
  }

  // MARK: - Internal Processing

  private func processBuffer(_ buffer: CMSampleBuffer) {
    if streamAnalyzer == nil {
      // Ignore buffers that arrive before start.
      return
    }

    if let pcmBuffer = AVAudioPCMBuffer(sampleBuffer: buffer) {
      if let analyzer = streamAnalyzer {
        analyzer.analyze(pcmBuffer, atAudioFramePosition: -1)
      }
    }
  }

  // Assumes the microphone format stays constant.

  private func areFormatsCompatible(_ newFormat: AVAudioFormat, _ currentFormat: AVAudioFormat?)
    -> Bool {
    guard let current = currentFormat else { return false }
    return newFormat.sampleRate == current.sampleRate
      && newFormat.channelCount == current.channelCount
  }

  private func reinitializeAnalyzer(with format: AVAudioFormat) {
    AppLogger.audio.info("SoundAnalysis: Initializing/Re-initializing analyzer. Format: \(format)")

    streamAnalyzer = SNAudioStreamAnalyzer(format: format)
    currentFormat = format

    // Re-add the request to the new analyzer.
    do {
      let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
      let observer = RealTimeResultsObserver { [weak self] classification in
        self?.onSoundDetected?(classification)
      }
      try streamAnalyzer?.add(request, withObserver: observer)
    } catch {
      AppLogger.audio.error("❌ Failed to re-add request on reinit: \(error)")
    }
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

    let analyzer = try SNAudioFileAnalyzer(url: url)
    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)

    let resultsObserver = GatingResultsObserver()
    try analyzer.add(request, withObserver: resultsObserver)

    _ = await analyzer.analyze()

    let classifications = resultsObserver.results
    var segments: [GatingSegment] = []

    // Open the gate when speech is the top classification with enough confidence.
    for result in classifications {
      let isSpeech = result.classifications.first { $0.identifier == "speech" }
      let confidence = isSpeech?.confidence ?? 0.0

      segments.append(
        GatingSegment(
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

// MARK: - Real-Time Observer

private class RealTimeResultsObserver: NSObject, SNResultsObserving {
  var callback: ((AudioClassification) -> Void)?

  init(callback: ((AudioClassification) -> Void)?) {
    self.callback = callback
  }

  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let classificationResult = result as? SNClassificationResult,
      let top = classificationResult.classifications.first
    else { return }

    let labelString = top.identifier
    let label = AudioLabel(rawValue: labelString) ?? .unknown

    guard top.confidence > 0.3 else { return }

    let classification = AudioClassification(
      timeRange: classificationResult.timeRange,
      label: label,
      confidence: Float(top.confidence)
    )

    callback?(classification)
  }

  func request(_ request: SNRequest, didFailWithError error: Error) {
    AppLogger.audio.error("SoundAnalysis: Real-time analysis failed: \(error.localizedDescription)")
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

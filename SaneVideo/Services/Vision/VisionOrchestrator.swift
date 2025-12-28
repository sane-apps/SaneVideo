//
//  VisionOrchestrator.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation
import Vision

/// Unified result containing all analysis data
struct VisionAnalysisResult: Sendable {
  var detectedText: [RecognizedText] = []
  var faces: [CMTime: CGRect] = [:]  // Keyframes for auto-framing
  var saliency: [CMTime: SaliencyResult] = [:]  // Keyframes for smart crop
  var privacyRegions: [PrivacyRegion] = []

  // Merge function
  mutating func merge(other: VisionAnalysisResult) {
    self.detectedText.append(contentsOf: other.detectedText)
    self.faces.merge(other.faces) { (_, new) in new }
    self.saliency.merge(other.saliency) { (_, new) in new }
    self.privacyRegions.append(contentsOf: other.privacyRegions)
  }
}

/// Configuration for what to analyze
struct VisionAnalysisConfig: Sendable {
  var detectText: Bool = false
  var detectFaces: Bool = false
  var detectSaliency: Bool = false
  var detectPrivacy: Bool = false  // Implies detectText
}

/// Orchestrates multiple Vision requests in a single video pass using VNVideoProcessor
/// Note: Does not conform to VisionOrchestratorProtocol due to Swift 6 actor isolation rules.
actor VisionOrchestrator {

  // MARK: - Dependencies
  // We reuse existing services mainly for their helper logic (parsing results),
  // but we will reimplement the DRIVER logic here.

  init() {}

  /// Preloads Vision models to reduce latency during first use
  /// Performs a dummy analysis on a 1x1 pixel buffer to force ANE spin-up.
  func warmup() {
    Task.detached(priority: .utility) {
      // Create 1x1 Dummy Buffer
      var pixelBuffer: CVPixelBuffer?
      let attrs =
        [
          kCVPixelBufferCGImageCompatibilityKey: true,
          kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

      let status = CVPixelBufferCreate(
        kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)

      if status == kCVReturnSuccess, let buffer = pixelBuffer {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        do {
          // Fire requests to wake up Neural Engine (Standard "Best Practice")
          try handler.perform([
            VNDetectFaceRectanglesRequest(),
            VNGenerateAttentionBasedSaliencyImageRequest(),
            VNRecognizeTextRequest()
          ])
          AppLogger.vision.info("👁️ VisionOrchestrator: Warmup Complete (ANE Ready)")
        } catch {
          // Warmup failure is non-fatal
        }
      }
    }
  }

  // MARK: - Main API

  /// Run all requested analysis in a single pass
  func analyze(
    videoURL: URL, config: VisionAnalysisConfig, progressHandler: ((Double) -> Void)? = nil
  ) async throws -> VisionAnalysisResult {

    // 1. Text Request
    if config.detectText || config.detectPrivacy {
      let textReq = VNRecognizeTextRequest { request, _ in
        if (request.results as? [VNRecognizedTextObservation]) != nil {
          // We need the timestamp.
          // VNVideoProcessor request completion handler doesn't pass time easily unless we track it?
          // actually, VNVideoProcessor calls completion per frame.
          // BUT, `VNRequest` results don't inherently have timestamps unless we correlate them.
          // Wait, `VNVideoProcessor` integration usually provides the time in the callbacks? No.
          // The standard pattern is `VNRequest` completion.
          // How do we get the TIME of the frame being processed?
          // Ah, `VNVideoProcessor` doesn't pass the CMTime to the completion block of the VNRequest directly.
        }
      }
      textReq.recognitionLevel = .accurate
      textReq.usesLanguageCorrection = true
      // We need a way to capture results WITH timestamps.
      // Using `VNVideoProcessor`, we typically don't get the connection easily.
      // ACTUALLY: The completion handler is called for EACH frame processed.
      // However, the `request` object doesn't store the "current time".
      // This is a known limitation of specific Vision APIs.

      // Re-evaluating VNVideoProcessor for this specific metadata need.
      // If we cannot get timestamps, we cannot map faces/saliency to Keyframes.
    }

    // Research Check: Does VNVideoProcessor expose timestamps?
    // It does via `VNVideoProcessor` analyze method... wait.

    // If VNVideoProcessor is too opaque, we fallback to our own robust AVAssetReader loop
    // BUT we make it a SINGLE loop.

    // VNVideoProcessor is great for "Classify this video", but for "Track this face at Time X",
    // we strictly need the CMTime.

    // PRO TIP: VNVideoProcessor is often less flexible than a well-tuned AVAssetReader loop for extracting timestamps.
    // Let's implement the "Industry Standard" Manually Tuned Loop (AVAssetReader)
    // which creates ONE buffer and fires MULTIPLE requests.

    return try await analyzeWithReader(
      videoURL: videoURL, config: config, progressHandler: progressHandler)
  }

  // MARK: - AVAssetReader Implementation (The "Triple Read" Killer)

  private func analyzeWithReader(
    videoURL: URL, config: VisionAnalysisConfig, progressHandler: ((Double) -> Void)?
  ) async throws -> VisionAnalysisResult {
    let asset = AVURLAsset(url: videoURL)
    let duration = try await asset.load(.duration)

    // Asset Reader Setup
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw NSError(
        domain: "VisionOrchestrator", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No video track"])
    }

    let reader = try AVAssetReader(asset: asset)
    let settings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false  // Zero-copy attempt
    reader.add(output)

    if !reader.startReading() {
      throw reader.error
        ?? NSError(
          domain: "VisionOrchestrator", code: -2,
          userInfo: [NSLocalizedDescriptionKey: "Reader failed start"])
    }

    // Vision Handler (reused)
    let requestHandlerOpts: [VNImageOption: Any] = [:]

    // Prepare Requests
    var requests: [VNRequest] = []

    // 1. Face Request
    var faceReq: VNDetectFaceRectanglesRequest?
    if config.detectFaces {
      faceReq = VNDetectFaceRectanglesRequest()
      requests.append(faceReq!)
    }

    // 2. Saliency
    var saliencyReq: VNGenerateAttentionBasedSaliencyImageRequest?
    if config.detectSaliency {
      saliencyReq = VNGenerateAttentionBasedSaliencyImageRequest()
      requests.append(saliencyReq!)
    }

    // 3. Text
    var textReq: VNRecognizeTextRequest?
    if config.detectText || config.detectPrivacy {
      textReq = VNRecognizeTextRequest()
      textReq?.recognitionLevel = .accurate
      textReq?.usesLanguageCorrection = true
      requests.append(textReq!)
    }

    // Result Storage
    var finalResult = VisionAnalysisResult()

    // Loop State
    let sampleInterval = CMTime(seconds: 0.5, preferredTimescale: 600)  // 2 FPS is usually enough for Magic Fix
    var nextSampleTime = CMTime.zero

    AppLogger.vision.info(
      "👁️ VisionOrchestrator: Starting unified pass for [\(config.detectText ? "Text " : "")\(config.detectFaces ? "Faces " : "")\(config.detectSaliency ? "Saliency" : "")]"
    )

    // Stats
    var frameCount = 0
    let processingStartTime = Date()
    let maxProcessingTime: TimeInterval = 300.0 // 5 minutes max
    var lastProgressTime = Date()

    while let sampleBuffer = output.copyNextSampleBuffer() {
      // ROBUSTNESS: Check for timeout
      if Date().timeIntervalSince(processingStartTime) > maxProcessingTime {
        AppLogger.vision.warning("👁️ VisionOrchestrator: Timeout after 5 minutes, stopping analysis")
        break
      }
      
      // ROBUSTNESS: Check for cancellation
      if Task.isCancelled {
        AppLogger.vision.info("👁️ VisionOrchestrator: Cancelled by user")
        break
      }
      
      // ROBUSTNESS: Yield periodically to prevent blocking
      if frameCount % 10 == 0 {
        await Task.yield()
      }
      let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

      // Cadence Control
      // Simple logic: if PTS >= nextSample, process.
      if pts >= nextSampleTime {
        guard let cvBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

        let handler = VNImageRequestHandler(
          cvPixelBuffer: cvBuffer, orientation: .up, options: requestHandlerOpts)

        // Perform ALL requests on this ONE buffer
        do {
          try handler.perform(requests)

          // Harvest Results

          // Faces
          if let fReq = faceReq, let results = fReq.results {
            if let firstFace = results.first {
              // CRITICAL: Flip Y from Vision's bottom-left origin to top-left origin
              let box = firstFace.boundingBox
              finalResult.faces[pts] = CGRect(x: box.minX, y: 1.0 - box.maxY, width: box.width, height: box.height)
            }
          }

          // Saliency
          if let sReq = saliencyReq, let results = sReq.results?.first,
            let salientObj = results.salientObjects?.first {
            let rect = salientObj.boundingBox
            let res = SaliencyResult(
              attentionPoint: CGPoint(x: rect.midX, y: 1.0 - rect.midY),  // Flip Y? Vision is bottom-left.
              attentionRect: CGRect(
                x: rect.minX, y: 1.0 - rect.maxY, width: rect.width, height: rect.height),
              objectnessRect: nil,
              confidence: salientObj.confidence
            )
            finalResult.saliency[pts] = res
          }

          // Text
          if let tReq = textReq, let results = tReq.results {
            let recognizedTexts = results.compactMap { obs -> RecognizedText? in
              guard let cand = obs.topCandidates(1).first else { return nil }
              return RecognizedText(
                text: cand.string,
                boundingBox: CGRect(
                  x: obs.boundingBox.minX,
                  y: 1.0 - obs.boundingBox.maxY,
                  width: obs.boundingBox.width,
                  height: obs.boundingBox.height
                ),
                confidence: cand.confidence,
                time: pts
              )
            }
            if !recognizedTexts.isEmpty {
              finalResult.detectedText.append(contentsOf: recognizedTexts)

              // Privacy
              if config.detectPrivacy {
                // Filter inline
                let privacy = recognizedTexts.filter {
                  $0.text.contains("@") || $0.text.filter { c in c.isNumber }.count >= 7
                    || $0.text.contains("http")
                }.map {
                  PrivacyRegion(
                    timeRange: CMTimeRange(
                      start: pts, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
                    frame: $0.boundingBox)
                }
                finalResult.privacyRegions.append(contentsOf: privacy)
              }
            }
          }

        } catch {
          // Log but continue
          // print("Vision error frame \(frameCount): \(error)")
        }

        nextSampleTime = pts + sampleInterval
        frameCount += 1

        // Progress (more frequent updates)
        let now = Date()
        if now.timeIntervalSince(lastProgressTime) >= 1.0 || frameCount % 5 == 0 {
          let progress = pts.seconds / duration.seconds
          progressHandler?(progress)
          lastProgressTime = now
        }
      }
    }

    let elapsed = Date().timeIntervalSince(processingStartTime)
    AppLogger.vision.info(
      "👁️ VisionOrchestrator: Single pass complete in \(String(format: "%.2f", elapsed))s. Processed \(frameCount) frames."
    )

    return finalResult
  }
}

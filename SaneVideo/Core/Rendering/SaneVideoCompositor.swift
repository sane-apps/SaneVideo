//
//  SaneVideoCompositor.swift
//  SaneVideo
//
//  Custom video compositor implementing AVVideoCompositing.
//  Enables application of Core Image filters (VideoEffect) and Transitions during playback
//  Refactored to use helper renderers.
//

@preconcurrency import AVFoundation
import AppKit
import CoreImage
import CoreMedia
import Vision

/// The Custom Compositor that renders frames
final class SaneVideoCompositor: NSObject, AVVideoCompositing {
  // MARK: - Configuration

  private static let pixelBufferAttributes: [String: any Sendable] = [
    kCVPixelBufferPixelFormatTypeKey as String: [
      kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ],
    kCVPixelBufferMetalCompatibilityKey as String: true
  ]

  // Concurrency: AVVideoCompositing protocol requires [String: any Sendable] in Swift 6.
  var sourcePixelBufferAttributes: [String: any Sendable]? {
    return SaneVideoCompositor.pixelBufferAttributes
  }

  var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
    return SaneVideoCompositor.pixelBufferAttributes
  }

  // Render Context (Shared Metal-backed CIContext)
  // Note: RenderingService.shared.ciContext is now dynamic based on thermal state
  private var ciContext: CIContext { RenderingService.shared.ciContext }
  private let commandQueue: MTLCommandQueue? = RenderingService.shared.commandQueue

  // MARK: - Render Loop

  func renderContextChanged(_: AVVideoCompositionRenderContext) {}

  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    // High-Performance rendering: Detach from caller context to avoid MainActor bottlenecks
    Task.detached(priority: .userInitiated) {
      await self.render(request)
    }
  }

  private func render(_ request: AVAsynchronousVideoCompositionRequest) async {
    // CRITICAL FIX: Ensure request is always finished, even on error
    // Use defer to guarantee finish() is called on all paths
    var outputPixelBuffer: CVPixelBuffer?
    var renderError: Error?
    
    defer {
      // CRITICAL FIX: Always finish the request, even if error occurred
      if let error = renderError {
        request.finish(with: error)
      } else if let buffer = outputPixelBuffer {
        request.finish(withComposedVideoFrame: buffer)
      } else {
        // Fallback: try to create empty buffer or finish with error
        if let emptyBuffer = request.renderContext.newPixelBuffer() {
          request.finish(withComposedVideoFrame: emptyBuffer)
        } else {
          request.finish(
            with: NSError(
              domain: "SaneVideoCompositor", code: -3,
              userInfo: [NSLocalizedDescriptionKey: "Failed to finish render request"]))
        }
      }
    }
    
    guard let instruction = request.videoCompositionInstruction as? SaneVideoCompositionInstruction,
      !instruction.layerInstructions.isEmpty
    else {
      // If instructions are empty (transient state), return an empty buffer or handle gracefully
      if let buffer = request.renderContext.newPixelBuffer() {
        outputPixelBuffer = buffer
        return
      } else {
        renderError = NSError(
          domain: "SaneVideoCompositor", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Empty instructions"])
        return
      }
    }

    guard let buffer = request.renderContext.newPixelBuffer() else {
      renderError = NSError(
        domain: "SaneVideoCompositor", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
      return
    }
    
    outputPixelBuffer = buffer

    // 2. Composite Layers (Video Tracks)
    var currentImage: CIImage?
    var processedTrackIDs = Set<CMPersistentTrackID>()

    for layerInstruction in instruction.layerInstructions.reversed() {
      let trackID = layerInstruction.trackID
      if processedTrackIDs.contains(trackID) { continue }

      var layerOutput: CIImage?

      // Transitions
      if let transitionMeta = instruction.activeTransitions.first(where: {
        $0.fromTrackID == trackID || $0.toTrackID == trackID
      }) {
        processedTrackIDs.insert(transitionMeta.fromTrackID)
        processedTrackIDs.insert(transitionMeta.toTrackID)

        if let fromImage = await getLayerImage(
          for: transitionMeta.fromTrackID, request: request, instruction: instruction),
          let toImage = await getLayerImage(
            for: transitionMeta.toTrackID, request: request, instruction: instruction) {
          let duration = transitionMeta.timeRange.duration.seconds
          let elapsed = request.compositionTime.seconds - transitionMeta.timeRange.start.seconds
          let progress = max(0, min(1, elapsed / duration))

          // Direct VideoTransition usage or helper
          let transitionModel = VideoTransition(type: transitionMeta.type)
          layerOutput = transitionModel.apply(
            from: fromImage, to: toImage, progress: CGFloat(progress))
        } else {
          if let toImg = await getLayerImage(
            for: transitionMeta.toTrackID, request: request, instruction: instruction) {
            layerOutput = toImg
          } else {
            layerOutput = await getLayerImage(
              for: transitionMeta.fromTrackID, request: request, instruction: instruction)
          }
        }

      } else {
        processedTrackIDs.insert(trackID)
        layerOutput = await getLayerImage(for: trackID, request: request, instruction: instruction)
      }

      if let newLayer = layerOutput {
        if let background = currentImage {
          currentImage = newLayer.composited(over: background)
        } else {
          currentImage = newLayer
        }
      }
    }

    // 3. Render Text Overlays
    if let resultImage = currentImage {
      let activeTextLayers = instruction.textLayers.filter {
        $0.timeRange.containsTime(request.compositionTime)
      }
      if !activeTextLayers.isEmpty {
        let renderSize = request.renderContext.size

        // Pro Feature: Face Detection for safe zone positioning
        var faceRects: [CGRect] = []

        // THERMAL OPTIMIZATION: Skip face detection if system is throttled
        let shouldDetectFaces =
          activeTextLayers.contains(where: { $0.isCaption }) && !ThermalManager.isThrottled

        if shouldDetectFaces {
          let request = VNDetectFaceRectanglesRequest()
          let handler = VNImageRequestHandler(ciImage: resultImage, options: [:])
          try? handler.perform([request])
          if let results = request.results {
            faceRects = results.map { $0.boundingBox }
          }
        }

        if let textImage = TextLayerRenderer.renderTextLayers(
          activeTextLayers, size: renderSize, faceRects: faceRects) {
          currentImage = textImage.composited(over: resultImage)
        }
      }
    }

    // 4. Render Cursor
    for (trackID, cursors) in instruction.trackCursorData {
      let compositionTime = request.compositionTime.seconds

      // Find the cursor metadata active at this composition time
      if let metadata = cursors.first(where: { $0.timeRange.containsTime(request.compositionTime) }) {
        // Calculate source time: (CompositionElapsed * speed) + sourceOffset
        let elapsedInComposition = compositionTime - metadata.timeRange.start.seconds
        let sourceTime = (elapsedInComposition * metadata.speed) + metadata.sourceOffset

        if let cursorImage = CursorRenderer.renderCursor(
          for: metadata.url, time: sourceTime, renderSize: request.renderContext.size) {
          if let final = currentImage {
            currentImage = cursorImage.composited(over: final)
          } else {
            currentImage = cursorImage
          }
        }
      }
    }

    // 5. Render Final
    // CRITICAL FIX: Wrap rendering in do-catch to handle errors
    do {
      guard let buffer = outputPixelBuffer else {
        renderError = NSError(
          domain: "SaneVideoCompositor", code: -4,
          userInfo: [NSLocalizedDescriptionKey: "Output buffer lost during rendering"])
        return
      }
      
      if let finalImage = currentImage {
        // Render directly to the output pixel buffer
        ciContext.render(finalImage, to: buffer)
      }
      // defer block will finish the request with the buffer
    } catch {
      // CRITICAL FIX: Capture error for defer block to handle
      renderError = error
    }
  }

  // Helper to render a single track layer
  private func getLayerImage(
    for trackID: CMPersistentTrackID, request: AVAsynchronousVideoCompositionRequest,
    instruction: SaneVideoCompositionInstruction
  ) async -> CIImage? {
    guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else { return nil }
    var layerImage = CIImage(cvPixelBuffer: sourceBuffer)

    // 0. Apply Privacy Blur
    if let privacyRanges = instruction.trackPrivacyRegions[trackID] {
      for (_, regions) in privacyRanges {  // Range check simplified, assuming pre-filtered or checking inside
        // In production, verify range contains time
        for region in regions {
          applyPrivacyRegion(region, to: &layerImage)
        }
      }
    }

    // Find corresponding layer instruction
    guard
      let layerInstruction = instruction.layerInstructions.first(where: { $0.trackID == trackID })
    else { return layerImage }

    // A. Apply Transform (Base Layer Instruction)
    var startTransform = CGAffineTransform.identity
    if layerInstruction.getTransformRamp(
      for: request.compositionTime, start: &startTransform, end: nil, timeRange: nil) {
      layerImage = layerImage.transformed(by: startTransform)
    }

    // A.2. Apply Keyframe Animation Transforms
    if let keyframeRanges = instruction.trackKeyframes[trackID] {
      for (range, animations) in keyframeRanges where range.containsTime(request.compositionTime) {
        let relativeTime = request.compositionTime - range.start
        for animation in animations {
          applyKeyframes(
            animation, relativeTime: relativeTime, renderSize: request.renderContext.size,
            to: &layerImage)
        }
      }
    }

    // B. Apply Effects
    if let effectRanges = instruction.trackEffects[trackID] {
      for (range, effects) in effectRanges where range.containsTime(request.compositionTime) {
        for effect in effects {
          applyVideoEffect(effect, to: &layerImage)
        }
      }
    }

    // C. Apply Background Effects
    if let bgEffectRanges = instruction.trackBackgroundEffects[trackID] {
      // THERMAL OPTIMIZATION: Skip background removal/blur if system is in emergency state
      if !ThermalManager.isEmergency {
        for (range, bgEffects) in bgEffectRanges where range.containsTime(request.compositionTime) {
          for bgEffect in bgEffects {
            await applyBackgroundEffect(
              bgEffect, to: &layerImage, visionService: instruction.visionService)
          }
        }
      } else {
        AppLogger.general.warning("🧊 Thermal Emergency: Skipping background effects")
      }
    }

    return layerImage
  }

  private func applyPrivacyRegion(_ region: PrivacyRegion, to image: inout CIImage) {
    let extent = image.extent
    let rect = CGRect(
      x: region.frame.origin.x * extent.width,
      y: (1.0 - region.frame.origin.y - region.frame.height) * extent.height,
      width: region.frame.width * extent.width,
      height: region.frame.height * extent.height
    )
    let crop = image.cropped(to: rect)
    let pixelate = CIFilter(name: "CIPixellate")!
    pixelate.setValue(crop, forKey: kCIInputImageKey)
    pixelate.setValue(max(5.0, extent.width / 50.0), forKey: "inputScale")
    if let output = pixelate.outputImage {
      image = output.composited(over: image)
    }
  }

  private func applyKeyframes(
    _ animation: KeyframeAnimation, relativeTime: CMTime, renderSize: CGSize,
    to image: inout CIImage
  ) {
    let scale = animation.value(for: .scale, at: relativeTime)
    let posX = animation.value(for: .positionX, at: relativeTime)
    let posY = animation.value(for: .positionY, at: relativeTime)
    let rotation = animation.value(for: .rotation, at: relativeTime)

    if scale != 1.0 || posX != 0 || posY != 0 || rotation != 0 {
      let centerX = image.extent.width / 2.0
      let centerY = image.extent.height / 2.0
      let moveX = CGFloat(posX) * renderSize.width
      let moveY = CGFloat(posY) * renderSize.height

      let kfTransform = CGAffineTransform.identity
        .translatedBy(x: centerX, y: centerY)
        .translatedBy(x: moveX, y: moveY)
        .scaledBy(x: CGFloat(scale), y: CGFloat(scale))
        .rotated(by: CGFloat(rotation) * .pi / 180.0)
        .translatedBy(x: -centerX, y: -centerY)

      image = image.transformed(by: kfTransform)
    }
  }

  private func applyVideoEffect(_ effect: VideoEffect, to image: inout CIImage) {
    if effect.type == .autoEnhance {
      let options: [CIImageAutoAdjustmentOption: Any] = [
        .enhance: true, .redEye: false, .features: []
      ]
      let filters = image.autoAdjustmentFilters(options: options)
      for filter in filters {
        filter.setValue(image, forKey: kCIInputImageKey)
        if let output = filter.outputImage { image = output }
      }
    } else if let filter = effect.createFilter() {
      filter.setValue(image, forKey: kCIInputImageKey)
      if let output = filter.outputImage { image = output }
    }
  }

  // MARK: - Kernels

  private static let chromaKeyKernel: CIColorKernel? = {
    return CIColorKernel(
      source:
        """
        kernel vec4 chromaKey(__sample s, vec3 targetColor, float threshold) {
          float dist = distance(s.rgb, targetColor);
          float alpha = step(threshold, dist);
          return vec4(s.rgb * alpha, alpha);
        }
        """
    )
  }()

  private func applyBackgroundEffect(
    _ bgEffect: BackgroundEffect, to image: inout CIImage, visionService: PersonSegmentationService?
  ) async {
    guard let visionService = visionService else { return }

    switch bgEffect {
    case .blur(let radius):
      if let blurred = try? await visionService.applyBackgroundBlur(
        to: image, blurRadius: radius, reuseRequest: true) {
        image = blurred
      }
    case .solidColor(let r, let g, let b, let a):
      let color = NSColor(red: r, green: g, blue: b, alpha: a)
      if let replaced = try? await visionService.replaceBackground(
        in: image, with: color, reuseRequest: true) {
        image = replaced
      }
    case .image(let url):
      if let bgCI = CIImage(contentsOf: url) {
        if let replaced = try? await visionService.replaceBackground(
          in: image, with: bgCI, reuseRequest: true) {
          image = replaced
        }
      }
    case .chromaKey(let r, let g, let b, let sensitivity):
      // GPU-accelerated Chroma Key using CIColorKernel to avoid expensive CPU Lut generation
      if let kernel = SaneVideoCompositor.chromaKeyKernel {
        let targetVector = CIVector(x: CGFloat(r), y: CGFloat(g), z: CGFloat(b))
        let threshold = CGFloat(sensitivity)  // Sensitivity is normalized 0-1

        if let output = kernel.apply(
          extent: image.extent, arguments: [image, targetVector, threshold]) {
          image = output
        }
      }
    }
  }
}

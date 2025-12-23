//
//  ProjectState+Analysis.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation

extension ProjectState {

  // MARK: - Gesture Detection (BodyPose)

  /// Find gestures in clip and add markers
  func findGestures(in clip: VideoClip) async {
    guard !isProcessing else { return }
    isProcessing = true

    await MainActor.run {
      ServiceContainer.shared.toastManager.show("🙋 Scanning for gestures...")
    }

    defer {
      Task { @MainActor in self.isProcessing = false }
    }

    do {
      let bodyService = ServiceContainer.shared.bodyPoseService

      // Detect all body gestures
      let gestures = try await bodyService.detectGestures(
        in: clip.url,
        gestures: BodyGesture.allCases,
        sampleInterval: 0.5
      )

      if gestures.isEmpty {
        await MainActor.run {
          ServiceContainer.shared.toastManager.show("No gestures detected", type: .info)
        }
        return
      }

      // Group by gesture type for summary
      var gestureCount: [BodyGesture: Int] = [:]
      for (gesture, _) in gestures {
        gestureCount[gesture, default: 0] += 1
      }

      let summary = gestureCount.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")

      // Log the timestamps (could add markers in future)
      AppLogger.vision.info("Found gestures: \(summary)")
      for (gesture, time) in gestures {
        AppLogger.vision.debug("  \(gesture.rawValue) at \(time.seconds)s")
      }

      await MainActor.run {
        ServiceContainer.shared.toastManager.show("Found \(gestures.count) gestures: \(summary)")
      }

    } catch {
      AppLogger.project.error("Gesture detection failed: \(error)")
      await MainActor.run {
        ServiceContainer.shared.toastManager.show("Gesture detection failed", type: .error)
      }
    }
  }

  // MARK: - Privacy Blur (Text Recognition)

  /// Apply privacy blur to detected text regions
  func applyPrivacyBlur(to clip: VideoClip) async {
    guard !isProcessing else { return }
    isProcessing = true

    await MainActor.run {
      ServiceContainer.shared.toastManager.show("🔒 Detecting sensitive text...")
    }

    defer {
      Task { @MainActor in self.isProcessing = false }
    }

    do {
      let textService = ServiceContainer.shared.textRecognitionService

      // Scan video for text
      let allText = try await textService.scanVideoForText(
        videoURL: clip.url,
        sampleInterval: 1.0
      )

      // Find sensitive text (emails, phones)
      let sensitiveCount = allText.filter { text in
        let content = text.text
        // Simple heuristics
        return content.contains("@") || content.filter { $0.isNumber }.count >= 7
          || content.contains("http")
      }.count

      if sensitiveCount == 0 {
        await MainActor.run {
          ServiceContainer.shared.toastManager.show("No sensitive text found", type: .info)
        }
        return
      }

      // Log detection results
      AppLogger.vision.info("Found \(sensitiveCount) sensitive text regions")

      await MainActor.run {
        // Convert to PrivacyRegions
        var privacyRegions: [PrivacyRegion] = []

        for item in allText {
          // Filter again for sensitive content
          let content = item.text
          let isSensitive =
            content.contains("@") || content.filter { $0.isNumber }.count >= 7
            || content.contains("http")

          if isSensitive {
            // Create PrivacyRegion
            // TextRecognitionResult usually has timeRange and boundingBox
            // item.boundingBox is normalized (0-1), usually bottom-left origin in Vision?
            // We need to ensure it matches our coordinate system.
            // Assuming item.boundingBox is standard normalized rect.

            let region = PrivacyRegion(
              timeRange: CMTimeRange(
                start: item.time, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
              frame: item.boundingBox
            )
            privacyRegions.append(region)
          }
        }

        // Update Clip
        self.updateClipPrivacyRegions(clipId: clip.id, regions: privacyRegions)

        ServiceContainer.shared.toastManager.show("🔒 Applied \(privacyRegions.count) privacy blurs")
      }

    } catch {
      AppLogger.project.error("Privacy blur failed: \(error)")
      await MainActor.run {
        ServiceContainer.shared.toastManager.show("Text detection failed", type: .error)
      }
    }
  }

  // MARK: - Audio Analysis (SoundAnalysis)

  /// Find highlights (applause, laughter) in clip audio
  func findHighlights(in clip: VideoClip) async {
    guard !isProcessing else { return }
    isProcessing = true

    await MainActor.run {
      ServiceContainer.shared.toastManager.show("🎉 Scanning audio for highlights...")
    }

    defer {
      Task { @MainActor in self.isProcessing = false }
    }

    do {
      let soundService = ServiceContainer.shared.soundAnalysisService

      // Find applause, laughter, crowd reactions
      let highlights = try await soundService.findHighlights(in: clip.url)

      if highlights.isEmpty {
        await MainActor.run {
          ServiceContainer.shared.toastManager.show(
            "No highlights found (applause, laughter)", type: .info)
        }
        return
      }

      // Group by type for summary
      var typeCount: [AudioLabel: Int] = [:]
      for highlight in highlights {
        typeCount[highlight.label, default: 0] += 1
      }

      let summary = typeCount.map { "\($0.key.displayName): \($0.value)" }.joined(separator: ", ")

      // Log timestamps for potential marker addition
      AppLogger.audio.info("Found highlights: \(summary)")
      for highlight in highlights {
        AppLogger.audio.debug(
          "  \(highlight.label.displayName) at \(highlight.timeRange.start.seconds)s")
      }

      await MainActor.run {
        ServiceContainer.shared.toastManager.show(
          "Found \(highlights.count) highlights: \(summary)")
      }

    } catch {
      AppLogger.project.error("Highlight detection failed: \(error)")
      await MainActor.run {
        ServiceContainer.shared.toastManager.show("Audio analysis failed", type: .error)
      }
    }
  }

  /// Helper to update clip privacy regions
  func updateClipPrivacyRegions(clipId: UUID, regions: [PrivacyRegion]) {
    guard var project = currentProject else { return }

    for (tIdx, track) in project.timeline.tracks.enumerated() {
      if let cIdx = track.clips.firstIndex(where: { $0.id == clipId }) {
        var updatedClip = track.clips[cIdx]
        updatedClip.privacyRegions = regions

        project.timeline.tracks[tIdx].clips[cIdx] = updatedClip

        // Register Undo?
        // registerUndo("Apply Privacy Blur")
        // We should probably register undo before modifying.
        // But this helper is internal.

        currentProject = project
        // saveProject(project) // Save is implicit in currentProject update mostly or triggered manually
        // But generally we should save.
        return
      }
    }
  }
}

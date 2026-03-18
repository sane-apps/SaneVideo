//
//  ProjectState+Import.swift
//  SaneVideo
//
//  Media import operations extracted from ClipManagement
//

import AVFoundation
import CoreMedia
import Foundation

extension ProjectState {

  // MARK: - Video Import

  func addVideoToTimeline(url: URL) async {
    NSLog("addVideoToTimeline called with: \(url.lastPathComponent)")

    let now = Date()
    if let lastURL = lastImportedURL, let lastTime = lastImportTime,
       lastURL == url, now.timeIntervalSince(lastTime) < 2.0 {
      NSLog("DEBOUNCE: Ignoring duplicate import of \(url.lastPathComponent)")
      AppLogger.project.warning("Ignoring duplicate import of \(url.lastPathComponent)")
      return
    }
    lastImportedURL = url
    lastImportTime = now

    NSLog("Attempting to import video from: \(url.path)")
    AppLogger.project.info("Attempting to import video from: \(url.path)")

    let nativeExtensions = ["mp4", "mov", "m4v"]
    let ext = url.pathExtension.lowercased()
    var targetURL = url

    if !nativeExtensions.contains(ext) {
      AppLogger.project.info("Non-native format detected (\(ext)). Requesting optimization...")
      if let optimizedURL = await optimizeMedia(url: url) {
        targetURL = optimizedURL
      } else {
        AppLogger.project.error("Optimization failed for \(ext) format")
        await MainActor.run {
          ServiceContainer.shared.toastManager.show("Failed to optimize \(ext) file. Format may not be supported.", type: .error)
        }
      }
    }

    do {
      var clip: VideoClip!
      var lastError: Error?

      for attempt in 1...5 {
        do {
          clip = try await ServiceContainer.shared.projectFileManager.loadClip(from: targetURL)
          break
        } catch {
          lastError = error

          if attempt == 1 && (error as NSError).domain == AVFoundationErrorDomain {
            AppLogger.project.warning("Native load failed. Attempting emergency optimization...")
            if let optimizedURL = await optimizeMedia(url: targetURL) {
              targetURL = optimizedURL
              continue
            }
          }

          AppLogger.project.warning("Attempt \(attempt) to load clip failed: \(error.localizedDescription)")
          if attempt < 5 {
            let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
          }
        }
      }

      if var resultClip = clip {
        let clickDataURL = targetURL.deletingPathExtension().appendingPathExtension("clicks.json")
        let cursorDataURL = targetURL.deletingPathExtension().appendingPathExtension("cursor.json")
        let keystrokeDataURL = targetURL.deletingPathExtension().appendingPathExtension("keys.json")
        if FileManager.default.fileExists(atPath: clickDataURL.path) {
          resultClip.clickDataURL = clickDataURL
          AppLogger.project.info("Attached click data for auto-zoom: \(clickDataURL.lastPathComponent)")
        }
        if FileManager.default.fileExists(atPath: cursorDataURL.path) {
          resultClip.cursorDataURL = cursorDataURL
          AppLogger.project.info("Attached cursor data for demo polish: \(cursorDataURL.lastPathComponent)")
        }
        if FileManager.default.fileExists(atPath: keystrokeDataURL.path) {
          resultClip.keystrokeDataURL = keystrokeDataURL
          AppLogger.project.info("Attached keystroke data for demo overlays: \(keystrokeDataURL.lastPathComponent)")
        }

        NSLog("Successfully loaded clip. Duration: \(resultClip.duration.seconds)s. Adding to timeline...")
        AppLogger.project.info("Successfully loaded clip. Duration: \(resultClip.duration.seconds)s. Adding to timeline...")
        addClip(resultClip)
        NSLog("Clip added to project!")
        AppLogger.project.info("Clip added.")
      } else if let error = lastError {
        throw error
      }
    } catch {
      AppLogger.project.error("Failed to load video clip: \(error)")
      let message = (error as NSError).domain == AVFoundationErrorDomain ? "Video format not supported or file damaged." : error.localizedDescription
      ServiceContainer.shared.toastManager.show("Import failed: \(message)", type: .error)
    }
  }

  func optimizeMedia(url: URL) async -> URL? {
    let ffmpeg = ServiceContainer.shared.ffmpegService
    guard await ffmpeg.isAvailable else {
      AppLogger.project.error("FFmpeg not available for optimization.")
      return nil
    }

    let optimizedDir = FileManager.default.currentDirectoryPath + "/Media/Optimized"
    let timestamp = Int(Date().timeIntervalSince1970)
    let outputURL = URL(fileURLWithPath: optimizedDir).appendingPathComponent("optimized_\(timestamp)_\(url.deletingPathExtension().lastPathComponent).mp4")

    await MainActor.run {
      self.isProcessing = true
      ServiceContainer.shared.toastManager.show("Optimizing Media for Editor...")
    }

    defer {
      Task { @MainActor in self.isProcessing = false }
    }

    do {
      AppLogger.project.info("Transcoding \(url.lastPathComponent) to \(outputURL.lastPathComponent)...")
      try await ffmpeg.convert(inputURL: url, outputURL: outputURL, codec: .h264, preset: .fast)
      AppLogger.project.info("Optimization complete: \(outputURL.path)")
      return outputURL
    } catch {
      AppLogger.project.error("Optimization failed: \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: - Audio Import

  func addAudioToTimeline(url: URL) async {
    let now = Date()
    if let lastURL = lastImportedURL, let lastTime = lastImportTime,
       lastURL == url, now.timeIntervalSince(lastTime) < 2.0 {
      AppLogger.project.warning("Ignoring duplicate import of \(url.lastPathComponent)")
      return
    }
    lastImportedURL = url
    lastImportTime = now

    AppLogger.project.info("Attempting to import audio from: \(url.path)")

    do {
      let clip = try await ServiceContainer.shared.projectFileManager.loadClip(from: url)
      AppLogger.project.info("Successfully loaded audio clip. Duration: \(clip.duration.seconds)s. Adding to timeline...")

      guard var project = currentProject else {
        startNewProject()
        await addAudioToTimeline(url: url)
        return
      }

      var timeline = project.timeline
      registerUndo("Add Audio")

      var targetTrackIndex = timeline.tracks.firstIndex { $0.type == .audio }
      if targetTrackIndex == nil {
        let existingCount = timeline.tracks.filter { $0.type == .audio }.count
        let newTrack = Track(name: "Audio \(existingCount + 1)", type: .audio, zIndex: timeline.tracks.count)
        timeline.addTrack(newTrack)
        targetTrackIndex = timeline.tracks.count - 1
      }

      guard let trackIndex = targetTrackIndex else {
        ServiceContainer.shared.toastManager.show("Failed to create audio track", type: .error)
        return
      }

      var track = timeline.tracks[trackIndex]

      var mutableClip = clip
      var cumulativeTime = CMTime.zero
      for existingClip in track.clips {
        cumulativeTime = CMTimeAdd(cumulativeTime, existingClip.effectiveDuration)
      }
      mutableClip.startTime = cumulativeTime

      track.clips.append(mutableClip)
      timeline.tracks[trackIndex] = track

      project.timeline = timeline
      currentProject = project
      saveProject(project)

      AppLogger.project.info("Added audio clip \(clip.id) to track '\(track.name)' at \(cumulativeTime.seconds)s")
      ServiceContainer.shared.toastManager.show("Added Audio: \(url.lastPathComponent)")
    } catch {
      AppLogger.project.error("Failed to load audio clip: \(error)")
      ServiceContainer.shared.toastManager.show("Audio import failed: \(error.localizedDescription)", type: .error)
    }
  }
}

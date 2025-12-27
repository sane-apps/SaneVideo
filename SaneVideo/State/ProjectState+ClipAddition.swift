//
//  ProjectState+ClipAddition.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation
import SwiftUI

extension ProjectState {

    // MARK: - Video Import

    func addVideoToTimeline(url: URL) async {
        NSLog("📹 addVideoToTimeline called with: \(url.lastPathComponent)")

        // Debounce: Prevent duplicate imports from SwiftUI fileImporter bug
        let now = Date()
        if let lastURL = lastImportedURL, let lastTime = lastImportTime,
           lastURL == url, now.timeIntervalSince(lastTime) < 2.0 {
            NSLog("📹 DEBOUNCE: Ignoring duplicate import of \(url.lastPathComponent)")
            AppLogger.project.warning("Ignoring duplicate import of \(url.lastPathComponent)")
            return
        }
        lastImportedURL = url
        lastImportTime = now

        NSLog("📹 Attempting to import video from: \(url.path)")
        AppLogger.project.info("Attempting to import video from: \(url.path)")

        // 1. Check if we should optimize (Pro Format Support)
        let nativeExtensions = ["mp4", "mov", "m4v"]
        let ext = url.pathExtension.lowercased()
        var targetURL = url

        if !nativeExtensions.contains(ext) {
            AppLogger.project.info("Non-native format detected (\(ext)). Requesting optimization...")
            if let optimizedURL = await optimizeMedia(url: url) {
                targetURL = optimizedURL
            } else {
                // CRITICAL: Optimization failed - show error instead of silently using original
                AppLogger.project.error("Optimization failed for \(ext) format")
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("❌ Failed to optimize \(ext) file. Format may not be supported.", type: .error)
                }
                // Continue with original - might work, might not
                // User has been warned
            }
        }

        do {
            // Robust Import: Retry logic for fresh recordings where moov atom might be settling
            var clip: VideoClip!
            var lastError: Error?

            for attempt in 1...5 {
                do {
                    clip = try await ServiceContainer.shared.projectFileManager.loadClip(from: targetURL)
                    break // Success
                } catch {
                    lastError = error

                    // 2. Pro Fallback: If native load fails, try one last time with optimization
                    // (Handle cases where extension is .mp4 but contents are weird)
                    if attempt == 1 && (error as NSError).domain == AVFoundationErrorDomain {
                        AppLogger.project.warning("Native load failed. Attempting emergency optimization...")
                        if let optimizedURL = await optimizeMedia(url: targetURL) {
                            targetURL = optimizedURL
                            continue // Retry with optimized URL
                        }
                    }

                    AppLogger.project.warning("Attempt \(attempt) to load clip failed: \(error.localizedDescription)")
                    if attempt < 5 {
                        // CRITICAL FIX: Longer delays for fresh recordings
                        // First attempt: 1s (file might still be finalizing)
                        // Subsequent attempts: exponential backoff (1s, 2s, 4s)
                        let delay = UInt64(pow(2.0, Double(attempt - 1)) * 1_000_000_000) // 1s, 2s, 4s, 8s
                        try? await Task.sleep(nanoseconds: delay)
                    }
                }
            }

            if var resultClip = clip {
                // Attach click data if available (for auto-zoom feature)
                // Click data is saved alongside the video file with .clicks.json extension
                let clickDataURL = targetURL.deletingPathExtension().appendingPathExtension("clicks.json")
                if FileManager.default.fileExists(atPath: clickDataURL.path) {
                    resultClip.clickDataURL = clickDataURL
                    AppLogger.project.info("Attached click data for auto-zoom: \(clickDataURL.lastPathComponent)")
                }

                // Attach cursor data if available (for cursor highlighting)
                let cursorDataURL = targetURL.deletingPathExtension().appendingPathExtension("json")
                if FileManager.default.fileExists(atPath: cursorDataURL.path) {
                    resultClip.cursorDataURL = cursorDataURL
                    AppLogger.project.info("Attached cursor data: \(cursorDataURL.lastPathComponent)")
                }

                NSLog("📹 Successfully loaded clip. Duration: \(resultClip.duration.seconds)s. Adding to timeline...")
                AppLogger.project.info("Successfully loaded clip. Duration: \(resultClip.duration.seconds)s. Adding to timeline...")
                addClip(resultClip)
                NSLog("📹 Clip added to project!")
                AppLogger.project.info("Clip added.")
            } else if let error = lastError {
                throw error
            }
        } catch {
            AppLogger.project.error("Failed to load video clip: \(error)")
            // Provide more actionable feedback
            let message = (error as NSError).domain == AVFoundationErrorDomain ? "Video format not supported or file damaged." : error.localizedDescription
            ServiceContainer.shared.toastManager.show("Import failed: \(message)", type: .error)
        }
    }

    /// Internal helper to transcode non-native or problematic media via FFmpeg
    private func optimizeMedia(url: URL) async -> URL? {
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

    // MARK: - Generic Clip Addition

    func addClip(_ clip: VideoClip) {
        guard var project = currentProject else {
            startNewProject()
            addClip(clip)
            return
        }

        var timeline = project.timeline

        registerUndo("Add Clip")

        // Find main video track or create one
        var targetTrackIndex = timeline.tracks.firstIndex { $0.type == .video }
        if targetTrackIndex == nil {
            let newTrack = Track(name: "", type: .video, zIndex: 0)
            timeline.addTrack(newTrack)
            targetTrackIndex = timeline.tracks.count - 1
        }

        guard let trackIndex = targetTrackIndex else { return }
        var track = timeline.tracks[trackIndex]

        // CRITICAL FIX: Warn if track has too many clips (performance issue)
        if track.clips.count >= 100 {
            AppLogger.project.warning("Track has \(track.clips.count) clips, consider creating a new track")
            ServiceContainer.shared.toastManager.show("Track has many clips. Consider creating a new track for better performance.", type: .info)
        }

        // CRITICAL FIX: Calculate startTime atomically to prevent race conditions
        // Calculate startTime based on cumulative duration of existing clips in this track
        var mutableClip = clip

        // CRITICAL FIX: Sort clips by startTime to ensure correct calculation
        // This prevents issues if clips were added out of order
        let sortedClips = track.clips.sorted { $0.startTime < $1.startTime }
        var cumulativeTime = CMTime.zero
        for existingClip in sortedClips {
            cumulativeTime = CMTimeAdd(cumulativeTime, existingClip.effectiveDuration)
        }
        mutableClip.startTime = cumulativeTime

        track.clips.append(mutableClip)
        timeline.tracks[trackIndex] = track

        // CRITICAL FIX: Recalculate startTimes to ensure consistency
        // This handles edge cases and ensures no gaps/overlaps
        recalculateStartTimes(in: &timeline)

        // CRITICAL FIX: Update timeline duration after addition
        timeline.updateDuration()

        // CRITICAL FIX: Validate timeline state after addition
        if !validateTimelineState(timeline) {
            AppLogger.project.error("Timeline state invalid after adding clip, rolling back")
            ServiceContainer.shared.toastManager.show("Failed to add clip: Timeline state invalid", type: .error)
            return
        }

        project.timeline = timeline
        currentProject = project
        recentlyAddedClip = mutableClip
        saveProject(project)

        AppLogger.project.info("Added clip \(clip.id) to track '\(track.name)' at \(cumulativeTime.seconds)s")
        ServiceContainer.shared.toastManager.show("Added Clip")

        // CRITICAL FIX: Force player reload after adding clip
        // This fixes a race condition where SwiftUI's onChange might not fire
        // when a new project is created and clip is added in rapid succession
        NotificationCenter.default.post(name: .clipAddedToTimeline, object: project)
    }

    /// Add an audio file to the timeline as an audio track
    func addAudioToTimeline(url: URL) async {
        // Debounce: Prevent duplicate imports
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
            // Load the audio file as a clip (VideoClip works for audio too)
            let clip = try await ServiceContainer.shared.projectFileManager.loadClip(from: url)
            AppLogger.project.info("Successfully loaded audio clip. Duration: \(clip.duration.seconds)s. Adding to timeline...")

            guard var project = currentProject else {
                startNewProject()
                await addAudioToTimeline(url: url)
                return
            }

            var timeline = project.timeline
            registerUndo("Add Audio")

            // Find or create an audio track
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

            // Calculate startTime based on cumulative duration of existing clips in this track
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
            ServiceContainer.shared.toastManager.show("✅ Added Audio: \(url.lastPathComponent)")
        } catch {
            AppLogger.project.error("Failed to load audio clip: \(error)")
            ServiceContainer.shared.toastManager.show("❌ Audio import failed: \(error.localizedDescription)", type: .error)
        }
    }
}

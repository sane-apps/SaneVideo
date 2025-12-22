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
        // Debounce: Prevent duplicate imports from SwiftUI fileImporter bug
        let now = Date()
        if let lastURL = lastImportedURL, let lastTime = lastImportTime,
           lastURL == url, now.timeIntervalSince(lastTime) < 2.0 {
            AppLogger.project.warning("Ignoring duplicate import of \(url.lastPathComponent)")
            return
        }
        lastImportedURL = url
        lastImportTime = now

        AppLogger.project.info("Attempting to import video from: \(url.path)")
        
        // 1. Check if we should optimize (Pro Format Support)
        let nativeExtensions = ["mp4", "mov", "m4v"]
        let ext = url.pathExtension.lowercased()
        var targetURL = url
        
        if !nativeExtensions.contains(ext) {
            AppLogger.project.info("Non-native format detected (\(ext)). Requesting optimization...")
            if let optimizedURL = await optimizeMedia(url: url) {
                targetURL = optimizedURL
            }
        }

        do {
            // Robust Import: Retry logic for fresh recordings where moov atom might be settling
            var clip: VideoClip!
            var lastError: Error?
            
            for attempt in 1...3 {
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
                    if attempt < 3 {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                    }
                }
            }
            
            if let resultClip = clip {
                AppLogger.project.info("Successfully loaded clip. Duration: \(resultClip.duration.seconds)s. Adding to timeline...")
                addClip(resultClip)
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
            let newTrack = Track(name: "Video 1", type: .video, zIndex: 0)
            timeline.addTrack(newTrack)
            targetTrackIndex = timeline.tracks.count - 1
        }

        guard let trackIndex = targetTrackIndex else { return }
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

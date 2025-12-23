//
//  ExportView+Actions.swift
//  SaneVideo
//
//  Refactored logic for ExportView.
//

import AppKit
import AVFoundation
import SwiftUI

extension ExportView {
    // MARK: - Export Actions

    func generateThumbnail() {
        guard let project = appState.currentProject,
              let firstTrack = project.timeline.tracks.first,
              let firstClip = firstTrack.clips.first else { return }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let fileName = "\(project.name)_Thumbnail.jpg"
        let outputURL = desktopURL.appendingPathComponent(fileName)

        // Capture services before Task (Swift 6 safety)
        let thumbnailService = ServiceContainer.shared.thumbnailService
        
        Task {
            do {
                let image = try await thumbnailService.generateBestThumbnail(for: firstClip.url)

                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [:])
                else {
                    throw ThumbnailError.frameExtractionFailed
                }

                try jpegData.write(to: outputURL)

                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                self.dismiss()
            } catch {
                self.exportError = error
                self.showingError = true
            }
        }
    }

    func exportStudyGuide() {
        guard let project = appState.currentProject else { return }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let fileName = "\(project.name)_StudyGuide.pdf"
        let outputURL = desktopURL.appendingPathComponent(fileName)

        let pdfService = ServiceContainer.shared.pdfService
        
        Task {
            do {
                try await pdfService.generateStudyGuide(for: project, outputURL: outputURL)
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                self.dismiss()
            } catch {
                self.exportError = error
                self.showingError = true
            }
        }
    }

    /// Export first clip as GIF using FFmpeg
    func exportAsGIF() {
        guard let project = appState.currentProject,
              let firstTrack = project.timeline.tracks.first,
              let firstClip = firstTrack.clips.first else {
            ServiceContainer.shared.toastManager.show("No clip to export", type: .error)
            return
        }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let fileName = "\(project.name)_\(Int(Date().timeIntervalSince1970)).gif"
        let outputURL = desktopURL.appendingPathComponent(fileName)

        isExporting = true
        exportProgress = 0.1

        let ffmpegService = ServiceContainer.shared.ffmpegService
        let toastManager = ServiceContainer.shared.toastManager

        Task {
            do {
                try await ffmpegService.exportAsGIF(
                    inputURL: firstClip.url,
                    outputURL: outputURL,
                    fps: 10,
                    width: 480,
                    startTime: firstClip.trimStart.seconds,
                    duration: min(firstClip.effectiveDuration.seconds, 10.0) // Max 10s for GIF
                ) { @Sendable progress in
                    Task { @MainActor in
                        self.exportProgress = progress
                    }
                }

                self.isExporting = false
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                toastManager.show("GIF exported!")
                self.dismiss()
            } catch {
                self.isExporting = false
                self.exportError = error
                self.showingError = true
            }
        }
    }

    /// Generate voiceover from captions using Apple TTS
    func generateVoiceover() {
        guard let project = appState.currentProject else {
            ServiceContainer.shared.toastManager.show("No project to export", type: .error)
            return
        }

        // Collect all captions from all clips
        let captions = project.timeline.tracks
            .flatMap { $0.clips }
            .flatMap { $0.captions }

        guard !captions.isEmpty else {
            ServiceContainer.shared.toastManager.show("No captions found - generate captions first", type: .error)
            return
        }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let fileName = "\(project.name)_Voiceover_\(Int(Date().timeIntervalSince1970)).m4a"
        let outputURL = desktopURL.appendingPathComponent(fileName)

        isExporting = true
        exportProgress = 0.1

        let voiceoverService = ServiceContainer.shared.voiceoverService
        let toastManager = ServiceContainer.shared.toastManager

        Task {
            do {
                // Convert to VoiceoverService captions
                let voiceoverCaptions = captions.map {
                    Caption(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
                }

                try await voiceoverService.generateVoiceoverFromCaptions(
                    voiceoverCaptions,
                    outputURL: outputURL
                )

                self.isExporting = false
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                toastManager.show("Voiceover generated!")
                self.dismiss()
            } catch {
                self.isExporting = false
                self.exportError = error
                self.showingError = true
            }
        }
    }

    /// Uses AIService to generate title and description from transcript
    func generateAITitleDescription() {
        guard let project = appState.currentProject else { return }

        // Collect all captions from all clips
        let transcript = project.timeline.tracks
            .flatMap { $0.clips }
            .flatMap { $0.captions }
            .map { $0.text }
            .joined(separator: " ")

        guard !transcript.isEmpty else {
            ServiceContainer.shared.toastManager.show("No transcript available", type: .error)
            return
        }

        isGeneratingAI = true

        let aiService = ServiceContainer.shared.aiService
        let toastManager = ServiceContainer.shared.toastManager

        Task {
            do {
                // Use dynamic provider selection (prefers on-device, falls back to cloud if available)
                let content = try await aiService.generateTitleAndDescriptionWithBestProvider(transcript: transcript)
                self.videoTitle = content.title
                self.videoDescription = content.description
                self.isGeneratingAI = false
                toastManager.show("AI generated title & description")
            } catch {
                self.isGeneratingAI = false
                self.exportError = error
                self.showingError = true
            }
        }
    }

    func startExport(uploadToYouTube: Bool = false) {
        guard let project = appState.currentProject else { return }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let fileName = "\(project.name)_\(Int(Date().timeIntervalSince1970)).mp4"
        let outputURL = desktopURL.appendingPathComponent(fileName)

        // Remove existing file if needed
        try? FileManager.default.removeItem(at: outputURL)

        isExporting = true
        exportProgress = 0

        Task {
            do {
                _ = try await exportEngine.export(
                    project: project,
                    settings: exportSettings,
                    outputURL: outputURL,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.exportProgress = progress
                        }
                    }
                )
                
                self.isExporting = false
                AppLogger.export.info("Export success: \(outputURL)")
                
                if uploadToYouTube {
                    await self.performYouTubeUpload(fileURL: outputURL)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    self.dismiss()
                }
            } catch {
                self.isExporting = false
                AppLogger.export.error("Export failed: \(error)")
                self.exportError = error
                self.showingError = true
            }
        }
    }

    func performYouTubeUpload(fileURL: URL) async {
        do {
            try await youtubeService.upload(
                videoURL: fileURL,
                title: videoTitle.isEmpty ? (appState.currentProject?.name ?? "My Video") : videoTitle,
                description: videoDescription
            )
            // Success alert or notification could be added here
            dismiss()
        } catch {
            exportError = error
            showingError = true
        }
    }

    // MARK: - Batch Export

    /// Exports multiple selected clips individually
    func startBatchExport() {
        let clips = selectedClips
        guard !clips.isEmpty else { return }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        let projectName = appState.currentProject?.name ?? "Untitled"

        // Capture settings before async context (Swift 6 compliance)
        let settings = exportSettings
        let engine = exportEngine

        isExporting = true
        exportProgress = 0

        Task {
            var successCount = 0
            var failedCount = 0
            let totalClips = clips.count
            var exportedURLs: [URL] = []

            for (index, clip) in clips.enumerated() {
                let fileName = "\(projectName)_\(clip.url.deletingPathExtension().lastPathComponent)_\(Int(Date().timeIntervalSince1970)).mp4"
                let outputURL = desktopURL.appendingPathComponent(fileName)

                // Remove existing file if needed
                try? FileManager.default.removeItem(at: outputURL)

                // Create a temporary project with just this clip
                var tempProject = VideoProject()
                tempProject.name = "\(projectName)_\(clip.url.deletingPathExtension().lastPathComponent)"

                // Add clip to first track
                let track = Track(name: "Export Track", type: .video, clips: [clip], zIndex: 0)
                tempProject.timeline.tracks.append(track)

                // Export using async (Swift 6 compliant)
                do {
                    _ = try await engine.export(
                        project: tempProject,
                        settings: settings,
                        outputURL: outputURL,
                        progressHandler: { progress in
                            // Update overall progress: (index + progress) / total
                            let overallProgress = (Double(index) + progress) / Double(totalClips)
                            Task { @MainActor in
                                self.exportProgress = overallProgress
                            }
                        }
                    )
                    exportedURLs.append(outputURL)
                    successCount += 1
                } catch {
                    failedCount += 1
                    AppLogger.export.error("Batch export failed for clip \(clip.url.lastPathComponent): \(error)")
                }
            }

            // Update UI on main actor
            isExporting = false
            exportProgress = 1.0

            if successCount > 0 {
                // Show exported files in Finder
                NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)

                if failedCount > 0 {
                    ServiceContainer.shared.toastManager.show("Exported \(successCount) of \(totalClips) clips. \(failedCount) failed.", type: .error)
                } else {
                    ServiceContainer.shared.toastManager.show("Successfully exported \(successCount) clip\(successCount == 1 ? "" : "s")!", type: .success)
                }
                dismiss()
            } else {
                exportError = ExportError.unknown
                showingError = true
            }
        }
    }

    func shareLink() {
        guard let project = appState.currentProject else { return }

        // Export to temp file first
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(project.name)_\(Int(Date().timeIntervalSince1970)).mp4"
        let outputURL = tempDir.appendingPathComponent(fileName)

        isExporting = true
        exportProgress = 0

        Task {
            do {
                _ = try await exportEngine.export(
                    project: project,
                    settings: exportSettings,
                    outputURL: outputURL,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.exportProgress = progress
                        }
                    }
                )
                
                self.isExporting = false
                let url = outputURL
                ServiceContainer.shared.shareLinkService.shareFile(at: url, from: nil)
            } catch {
                self.isExporting = false
                AppLogger.export.error("Share export failed: \(error)")
                self.exportError = error
                self.showingError = true
            }
        }
    }
}

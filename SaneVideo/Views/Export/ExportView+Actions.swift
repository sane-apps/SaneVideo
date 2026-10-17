import AppKit
import AVFoundation
import SwiftUI

@MainActor
extension ExportView {
    // MARK: - Export Actions

    func generateThumbnail() {
        guard let project = appState.currentProject,
              let firstTrack = project.timeline.tracks.first,
              let firstClip = firstTrack.clips.first else { return }

        let outputURL = ExportDestination.url(for: project.name, suffix: "Thumbnail", ext: "jpg")

        // Capture services before Task (Swift 6 safety)
        let thumbnailService = ServiceContainer.shared.thumbnailService

        Task {
            do {
                let image = try await thumbnailService.generateBestThumbnail(for: firstClip.url)

                guard let tiffData = image.value.tiffRepresentation,
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

    /// Export the first 10 seconds of the first clip as a GIF
    func exportAsGIF() {
        guard let project = appState.currentProject,
              let firstTrack = project.timeline.tracks.first,
              let firstClip = firstTrack.clips.first
        else {
            ServiceContainer.shared.toastManager.show("No clip to export", type: .error)
            return
        }

        let outputURL = ExportDestination.url(for: project.name, ext: "gif")

        isExporting = true
        exportProgress = 0.1

        let toastManager = ServiceContainer.shared.toastManager

        Task {
            do {
                try await GIFExporter.export(
                    inputURL: firstClip.url,
                    outputURL: outputURL,
                    fps: 10,
                    width: 480,
                    startTime: firstClip.trimStart.seconds,
                    duration: min(firstClip.effectiveDuration.seconds, 10.0)
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

        let captions = project.timelineCaptions

        guard !captions.isEmpty else {
            ServiceContainer.shared.toastManager.show("No captions found - generate captions first", type: .error)
            return
        }

        let outputURL = ExportDestination.url(for: project.name, suffix: "Voiceover", ext: "m4a")

        isExporting = true
        exportProgress = 0.1

        let voiceoverService = ServiceContainer.shared.voiceoverService
        let toastManager = ServiceContainer.shared.toastManager

        Task {
            do {
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

    func startExport() {
        guard let project = appState.currentProject else {
            ServiceContainer.shared.toastManager.show("No project to export", type: .error)
            return
        }

        let hasClips = project.timeline.tracks.contains { !$0.clips.isEmpty }
        guard hasClips else {
            ServiceContainer.shared.toastManager.show("Cannot export empty timeline. Add clips first.", type: .error)
            return
        }

        let outputURL = ExportDestination.url(for: project.name, ext: exportSettings.fileExtension)

        Task {
            await startExportWithValidation(project: project, outputURL: outputURL)
        }
    }

    private func startExportWithValidation(project: VideoProject, outputURL: URL) async {
        // Estimate file size: duration (seconds) × bitrate (bits/sec) / 8 = bytes
        let duration = project.timeline.duration.seconds
        let videoBitrate = Double(exportSettings.bitrate) // bits per second
        let audioBitrate = 192_000.0 // 192 kbps
        let totalBitrate = videoBitrate + audioBitrate
        let estimatedBytes = Int64((totalBitrate * duration) / 8.0)
        // Add 20% overhead for container, metadata, etc.
        let requiredSpace = Int64(Double(estimatedBytes) * 1.2)

        do {
            let outputVolume = outputURL.deletingLastPathComponent()
            let values = try outputVolume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                if available < requiredSpace {
                    let requiredMB = ByteCountFormatter.string(fromByteCount: requiredSpace, countStyle: .file)
                    let availableMB = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                    ServiceContainer.shared.toastManager.show("Insufficient disk space. Required: \(requiredMB), Available: \(availableMB)", type: .error)
                    return
                }
            }
        } catch {
            AppLogger.export.warning("Failed to check disk space: \(error.localizedDescription). Proceeding with export.")
            // Continue with export if check fails (better than blocking user)
        }

        isExporting = true
        exportProgress = 0

        estimatedTotalBytes = requiredSpace
        speedTracker.startTracking(totalBytes: estimatedTotalBytes)

        Task {
            do {
                _ = try await exportEngine.export(
                    project: project,
                    settings: exportSettings,
                    outputURL: outputURL,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.exportProgress = progress
                            let bytesProcessed = Int64(Double(self.estimatedTotalBytes) * progress)
                            self.speedTracker.update(bytesProcessed: bytesProcessed, totalBytes: self.estimatedTotalBytes)
                        }
                    }
                )

                self.isExporting = false
                self.speedTracker.reset()
                AppLogger.export.info("Export success: \(outputURL.lastPathComponent)")

                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                self.dismiss()
            } catch {
                self.isExporting = false
                self.speedTracker.reset()
                AppLogger.export.error("Export failed: \(error)")
                self.exportError = error
                self.showingError = true
            }
        }
    }

    // MARK: - Batch Export

    /// Exports multiple selected clips individually (parallelized via BatchCoordinator)
    func startBatchExport() {
        let clips = selectedClips
        guard !clips.isEmpty else { return }

        let exportFolder = ExportDestination.folder
        let projectName = appState.currentProject?.name ?? "Untitled"

        // Capture settings before async context (Swift 6 compliance)
        let settings = exportSettings
        let engine = exportEngine

        isExporting = true
        exportProgress = 0

        Task {
            let totalClips = clips.count
            let timestamp = Int(Date().timeIntervalSince1970)

            // Use BatchCoordinator for parallel export (I/O bound, so use 2 workers)
            let ext = settings.fileExtension
            let results = await BatchCoordinator.execute(
                items: clips,
                config: .ioBound, // 2 concurrent workers for I/O-bound operations
                operation: { clip, index in
                    let fileName = "\(projectName)_\(clip.url.deletingPathExtension().lastPathComponent)_\(timestamp).\(ext)"
                    let outputURL = exportFolder.appendingPathComponent(fileName)

                    try? FileManager.default.removeItem(at: outputURL)

                    var tempProject = VideoProject()
                    tempProject.name = "\(projectName)_\(clip.url.deletingPathExtension().lastPathComponent)"

                    let track = Track(name: "Export Track", type: .video, clips: [clip], zIndex: 0)
                    tempProject.timeline.tracks.append(track)

                    _ = try await engine.export(
                        project: tempProject,
                        settings: settings,
                        outputURL: outputURL,
                        progressHandler: { clipProgress in
                            let overallProgress = (Double(index) + clipProgress) / Double(totalClips)
                            Task { @MainActor in
                                self.exportProgress = overallProgress
                            }
                        }
                    )
                },
                progressHandler: { completed, total in
                    Task { @MainActor in
                        self.exportProgress = Double(completed) / Double(total)
                    }
                }
            )

            isExporting = false
            exportProgress = 1.0

            let successCount = results.filter { $0.success }.count
            let failedCount = results.filter { !$0.success }.count

            var exportedURLs: [URL] = []
            for (index, result) in results.enumerated() where result.success {
                let fileName = "\(projectName)_\(clips[index].url.deletingPathExtension().lastPathComponent)_\(timestamp).\(ext)"
                let outputURL = exportFolder.appendingPathComponent(fileName)
                exportedURLs.append(outputURL)
            }

            if successCount > 0 {
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
        guard !project.timeline.tracks.allSatisfy({ $0.clips.isEmpty }) else {
            exportError = ExportError.invalidProject("Add at least one clip before sharing an exported file.")
            showingError = true
            ServiceContainer.shared.toastManager.show("Add a clip before sharing.", type: .error)
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let ext = exportSettings.fileExtension
        let fileName = "\(project.name)_\(Int(Date().timeIntervalSince1970)).\(ext)"
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

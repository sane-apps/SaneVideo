import AVFoundation
import Foundation
import SwiftUI

extension AppState {
    // MARK: - Recording Actions

    func toggleRecording() {
        if recordingState.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        AppLogger.recording.info("🔴 AppState: Initiating recording sequence...")

        // RecordingState owns permission preflight. Starting the camera here creates
        // duplicate camera permission requests and can wedge first-use camera access.
        recordingState.startRecording(
            isScreenSharing: windowManager.isScreenSharing,
            includeCameraOverlay: cameraEnabled || cameraState.isActive
        )

        // Hide the app while screen sharing so its window is not recorded.
        if windowManager.isScreenSharing {
            windowManager.minimizeMainWindow()
        }
    }

    func stopRecording() {
        NSLog("🛑 AppState.stopRecording called. appMode=\(appMode), isRecording=\(recordingState.isRecording)")

        // Allow stop even if the mode changed, so the user is never stuck.
        guard recordingState.isRecording else {
            NSLog("🛑 AppState: stopRecording ignored (not recording)")
            AppLogger.recording.warning("🛑 AppState: stopRecording ignored (not recording)")
            return
        }

        AppLogger.recording.info("📹 AppState: Stopping recording...")
        NSLog("📹 AppState: Stopping recording...")

        recordingState.stopRecording { [weak self] url in
            guard let self else { return }

            Task { @MainActor in
                // Update state flags before UI work to avoid races.
                let wasScreenSharing = self.windowManager.isScreenSharing

                if wasScreenSharing {
                    self.windowManager.isScreenSharing = false
                }

                if let project = self.projectState.currentProject, project.speakerNotes.isVisible {
                    self.setTeleprompterVisible(false)
                } else {
                    self.windowManager.hideTeleprompter()
                }

                // The cameraEnabled setter stops the camera.
                self.cameraEnabled = false

                self.windowManager.restoreMainWindow()

                // PiP hides here because isScreenSharing is now false.
                self.windowManager.updatePiPState(isCameraActive: false, isRecording: false)
                self.windowManager.hideFloatingControls()
            }

            if let url = url {
                Task { @MainActor in
                    AppLogger.general.info("📹 Recording saved: \(url.lastPathComponent)")
                    self.handleRecordingFinished(url: url)
                }
            } else {
                AppLogger.general.warning("⚠️ No recording URL returned")
                let isTesting = TestEnvironment.isUITesting
                if !isTesting {
                    Task { @MainActor in
                        ServiceContainer.shared.toastManager.show(
                            "⚠️ Recording cancelled or empty", type: .error
                        )
                    }
                }
            }
        }
    }

    func handleRecordingFinished(url: URL) {
        AppLogger.recording.info("📹 handleRecordingFinished called with: \(url.lastPathComponent)")

        // The cameraEnabled setter stops the camera.
        cameraEnabled = false
        windowManager.updatePiPState(isCameraActive: false, isRecording: false)
        ServiceContainer.shared.transcriptionCoordinator.warmUp()

        Task { @MainActor in
            let thumbnail = await generateQuickThumbnail(for: url)

            self.quickAccessRecordingURL = url
            self.quickAccessThumbnail = thumbnail
            self.showQuickAccessOverlay = true

            self.windowManager.restoreMainWindow()

            ServiceContainer.shared.soundManager.playSuccess()
        }
        // Every recording becomes a project right away, whatever the user picks next.
        recordingImportTask = Task { @MainActor in
            await self.addRecordingAsProject(url: url)
        }
    }

    private func generateQuickThumbnail(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)

        guard let duration = try? await asset.load(.duration) else {
            return nil
        }

        // A frame 10% in usually shows real content.
        let time = CMTimeMultiplyByFloat64(duration, multiplier: 0.1)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            AppLogger.general.warning("Failed to generate quick thumbnail: \(error)")
            return nil
        }
    }

    func handleQuickAccessEdit() {
        showQuickAccessOverlay = false
        Task { @MainActor in
            await recordingImportTask?.value
            switchToEditing()
        }
    }

    func handleQuickAccessSave() {
        showQuickAccessOverlay = false
        ServiceContainer.shared.toastManager.show("Saved to Projects")
        // Ready for the next take.
        if appMode == .recording { restoreCameraIfWanted() }
    }

    func handleQuickAccessShare() {
        showQuickAccessOverlay = false
        Task { @MainActor in
            await recordingImportTask?.value
            switchToEditing()
            showExportSheet = true
        }
    }

    func dismissQuickAccessOverlay() {
        showQuickAccessOverlay = false
        quickAccessRecordingURL = nil
        quickAccessThumbnail = nil
        if appMode == .recording { restoreCameraIfWanted() }
    }

    private func addRecordingAsProject(url: URL) async {
        projectState.startNewProject(named: url.deletingPathExtension().lastPathComponent)
        // Give AVAssetWriter's final rename a moment to become visible.
        try? await Task.sleep(for: .milliseconds(400))
        await projectState.addVideoToTimeline(url: url)
        if let firstClip = projectState.currentProject?.timeline.tracks.flatMap(\.clips).first {
            selectedClipIds = [firstClip.id]
        }
    }

    // MARK: - Coordination Actions

    func togglePause() {
        recordingState.togglePause(isScreenSharing: windowManager.isScreenSharing)
    }

    func toggleScreenShare() {
        NSLog("🖥️ toggleScreenShare() called. Current isScreenSharing=\(windowManager.isScreenSharing)")

        // Block concurrent toggles; ending screen sharing twice would run cleanup twice.
        guard !windowManager.isTogglingScreenShare else {
            NSLog("🖥️ toggleScreenShare: Already toggling, ignoring")
            AppLogger.window.warning("toggleScreenShare: Already toggling, ignoring duplicate call")
            return
        }

        windowManager.isTogglingScreenShare = true
        // No defer here: the flag resets when the Task finishes, which prevents races.

        let wasScreenSharing = windowManager.isScreenSharing
        NSLog("🖥️ toggleScreenShare: wasScreenSharing=\(wasScreenSharing)")

        if wasScreenSharing {
            // If recording, switch to camera before stopping screen share so the recording continues.
            if recordingState.isRecording {
                let newSource: RecordingSource = .camera
                AppLogger.recording.info("🔄 AppState: Switching from screen to camera recording")
                recordingState.switchSource(newSource)

                Task { @MainActor in
                    // Brief delay for screen recorder cleanup (switch itself is instant)
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

                    windowManager.restoreMainWindow()
                    windowManager.isScreenSharing = false
                    windowManager.updatePiPState(
                        isCameraActive: cameraState.isActive,
                        isRecording: recordingState.isRecording
                    )

                    windowManager.isTogglingScreenShare = false
                    ServiceContainer.shared.toastManager.show("📷 Switched to Camera Recording")
                }
            } else {
                NSLog("🖥️ toggleScreenShare: Not recording, stopping screen share cleanly...")

                Task { @MainActor in
                    NSLog("🖥️ Step 1: Stopping screen recorder stream...")
                    if let screenRecorder = recordingState.engine?.screenRecorder {
                        await screenRecorder.stop()
                        NSLog("🖥️ Step 1: ✅ Screen recorder stream stopped")
                    }

                    NSLog("🖥️ Step 2: Updating state...")
                    windowManager.isScreenSharing = false

                    NSLog("🖥️ Step 3: Hiding PiP...")
                    windowManager.updatePiPState(
                        isCameraActive: cameraState.isActive,
                        isRecording: false
                    )

                    NSLog("🖥️ Step 4: Waiting for window cleanup...")
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

                    // Leave SCContentSharingPicker active so macOS remembers the last selection.
                    NSLog("🖥️ Step 5: Picker remains active for selection persistence")

                    NSLog("🖥️ Step 6: Restoring main window...")
                    windowManager.restoreMainWindow()

                    windowManager.isTogglingScreenShare = false
                    NSLog("🖥️ toggleScreenShare: ✅ Sequence complete")
                }
            }
        } else {
            NSLog("🖥️ toggleScreenShare: Starting screen share...")

            // Leave the camera off unless the user turns it on; auto-starting it breaks screen-only demos and first-use privacy expectations.
            NSLog("🖥️ toggleScreenShare: Leaving camera state unchanged for screen-only capture")

            windowManager.isScreenSharing = true

            // Do not show PiP yet or it appears in the picker; onContentSelected shows it after the user picks.
            NSLog("🖥️ toggleScreenShare: Deferring PiP display until after content selection")

            Task { @MainActor in
                // Small delay to let UI settle
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                if let screenRecorder = self.recordingState.engine?.screenRecorder {
                    do {
                        try await screenRecorder.start()
                        NSLog("🖥️ Screen share flow handed off to ScreenRecorder")
                    } catch {
                        AppLogger.window.error("toggleScreenShare: Failed to start screen share: \(error.localizedDescription)")
                        self.windowManager.isScreenSharing = false
                        self.windowManager.restoreMainWindow()
                        ServiceContainer.shared.errorPresenter.present(
                            AppError.recordingEngineError("Screen sharing failed: \(error.localizedDescription)")
                        )
                    }
                }

                windowManager.isTogglingScreenShare = false
            }
        }
    }

    func toggleCamera() {
        cameraEnabled = !(cameraEnabled || cameraState.isActive)
        UserDefaults.standard.set(cameraEnabled, forKey: AppState.cameraWantedKey)
    }

    func toggleMic() {
        recordingState.toggleMic()
    }

    func togglePiPVisibility() {
        Task { @MainActor in
            self.windowManager.togglePiPVisibility(
                isCameraActive: self.cameraState.isActive,
                isRecording: self.recordingState.isRecording
            )
        }
    }

    // MARK: - Project Actions

    /// Import owns the document until its sheet closes. Do not queue another command behind it.
    var projectCommandsEnabled: Bool { !showingImportPicker }

    func performProjectCommand(_ action: () -> Void) {
        guard projectCommandsEnabled else { return }
        action()
    }

    func importVideo() {
        projectState.showImportPicker()
    }

    func startNewRecording() {
        switchToRecording()
        projectState.startNewProject()
        windowManager.restoreMainWindow()

        if !TestEnvironment.isTesting {
            Task { @MainActor [weak self] in
                self?.prepareCameraPreviewIfNeeded()
            }
        }
    }

    func addVideoToTimeline(url: URL) {
        Task { @MainActor in
            await projectState.addVideoToTimeline(url: url)

            guard projectState.currentProject != nil else { return }

            switchToEditing()
            windowManager.restoreMainWindow()
        }
    }

    func openTeleprompterScript() {
        ensureCurrentProjectExists()
        showTeleprompterScriptSheet = true
    }

    func toggleTeleprompter() {
        ensureCurrentProjectExists()

        guard let project = projectState.currentProject else { return }
        if !project.speakerNotes.hasContent, !project.speakerNotes.isVisible {
            showTeleprompterScriptSheet = true
            return
        }

        setTeleprompterVisible(!project.speakerNotes.isVisible)
    }

    func setTeleprompterVisible(_ visible: Bool, notesOverride: SpeakerNotes? = nil) {
        ensureCurrentProjectExists()

        guard let project = projectState.currentProject else { return }
        var notes = notesOverride ?? project.speakerNotes

        if visible, !notes.hasContent {
            notes.isVisible = false
            projectState.updateSpeakerNotes(notes)
            windowManager.hideTeleprompter()
            showTeleprompterScriptSheet = true
            return
        }

        notes.isVisible = visible
        projectState.updateSpeakerNotes(notes)

        if visible {
            windowManager.showTeleprompter()
        } else {
            windowManager.hideTeleprompter()
        }
    }

    private func ensureCurrentProjectExists() {
        if projectState.currentProject == nil {
            projectState.startNewProject()
        }
    }
}

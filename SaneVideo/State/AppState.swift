//
//  AppState.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
@Observable
class AppState {

  enum AppMode {
    case recording
    case editing
  }

  // MARK: - App Mode

  var appMode: AppMode = .recording
  var isTesting: Bool = false
  @ObservationIgnored private var isBootstrapped = false

  // MARK: - Sub-States

  var recordingState = RecordingState()
  var projectState = ProjectState()
  var cameraState = CameraState()
  var windowManager = WindowManager()
  var playbackState = PlaybackState()

  // MARK: - Recording Settings

  /// User's intent for camera state - setting this automatically starts/stops camera
  /// Use cameraState.isActive to check if camera is actually running
  var cameraEnabled = false {
    didSet {
      guard cameraEnabled != oldValue else { return }
      if cameraEnabled {
        cameraState.startCamera()
      } else {
        cameraState.stopCamera()
      }
    }
  }
  // microphoneEnabled removed - use isMicActive proxy (delegates to RecordingState.isMicActive)

  // MARK: - Error Handling

  // Delegated to ServiceContainer.shared.errorPresenter

  // MARK: - Export Sheet (for ⌘E shortcut)

  var showExportSheet = false

  // MARK: - Quick Access Overlay (post-recording)

  var showQuickAccessOverlay = false
  var quickAccessRecordingURL: URL?
  var quickAccessThumbnail: NSImage?

  // MARK: - Timeline Selection (for multi-select and batch operations)

  var selectedClipIds: Set<UUID> = []  // Multi-select support for batch operations
  private var cancellables = Set<AnyCancellable>()

  init(recordingState: RecordingState? = nil) {
    if let injectedState = recordingState {
      self.recordingState = injectedState
    }

    setupMode()
    setupEnvironment()
    setupStateCoordination()
    setupErrorHandling()

    NSLog("🚀 AppState: init completed (appMode: \(appMode))")
    AppLogger.general.info("🚀 AppState: init completed")
  }

  private func setupMode() {
    if TestEnvironment.shouldOpenEditor {
      AppLogger.general.info("🧪 AppState: Detected Editor Mode. Initializing .editing")
      NSLog("🧪 AppState: Detected Editor Mode. Initializing .editing")
      self.appMode = .editing
    } else {
      NSLog("🧪 AppState: Recording Mode (default)")
      self.appMode = .recording
    }
  }

  private func setupEnvironment() {
    self.isTesting = TestEnvironment.isUITesting
    TestEnvironment.logState()

    if isTesting {
      AppLogger.general.info("🧪 AppState: Test Environment Detected")
      NSLog("🧪 AppState: Test Environment Detected")
    } else {
      ServiceContainer.shared.audioService.start()
    }

    // Bootstrap if needed
    if TestEnvironment.shouldOpenEditor {
      NSLog("🧪 AppState: Calling bootstrapEditorForTesting()...")
      Task {
        await self.bootstrapEditorForTesting()
      }
    }
  }

  // MARK: - Test Helpers

  func bootstrapEditorForTesting() async {
    guard !isBootstrapped else {
      NSLog("🧪 AppState: Already bootstrapped, skipping")
      return
    }
    isBootstrapped = true

    AppLogger.general.info("🧪 Bootstrapping Editor for UI Tests (REAL ASSET MODE)...")
    NSLog("🧪 Bootstrapping Editor for UI Tests (REAL ASSET MODE)...")

    let testAssetURL = TestEnvironment.mockAssetURL

    AppLogger.general.info("🧪 AppState: Bootstrapping editor...")

    // Create Project IMMEDATELY so UI exists
    projectState.startNewProject()

    // Wait for file locally (idempotent setup)
    if !FileManager.default.fileExists(atPath: testAssetURL.path) {
      AppLogger.general.error("❌ AppState: Test asset NOT FOUND at \(testAssetURL.path)")
      NSLog("❌ AppState: Test asset NOT FOUND at \(testAssetURL.path)")
    } else {
      // Use STANDARD import logic to ensure everything (tracks, duration) is valid
      AppLogger.general.info("🧪 Importing test asset: \(testAssetURL.path)")
      NSLog("🧪 Importing test asset: \(testAssetURL.path)")
      await projectState.addVideoToTimeline(url: testAssetURL)
    }

    // Switch Mode
    await MainActor.run {
      self.switchToEditing()
      self.windowManager.restoreMainWindow()

      // Explicitly select the newly added clip to reveal inspector tools
      if let firstClip = self.projectState.currentProject?.timeline.tracks.first?.clips.first {
        self.selectedClipIds = [firstClip.id]
        AppLogger.general.info("🧪 Explicitly selected clip: \(firstClip.id)")
      }

      let projectName = self.projectState.currentProject?.name ?? "nil"
      AppLogger.general.info(
        "🧪 Switched to Editing Mode and restored window. Project: \(projectName)")
      NSLog("🧪 Switched to Editing Mode and restored window. Project: \(projectName)")
    }

    // Final settle delay for UI layout
    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
    NSLog("🧪 AppState: Bootstrap complete and settled.")
  }

  // REMOVED: generateTestVideo and createTestPixelBuffer to avoid AVAssetWriter hangs

  private func setupStateCoordination() {
    // 1. Listen for External Screen Stop Requests
    recordingState.onRequestScreenShareStop = { [weak self] in
      // Only toggle if currently sharing
      if self?.windowManager.isScreenSharing == true {
        self?.toggleScreenShare()
      }
    }

    // 2. Coordinate dependencies using Async tasks or direct triggers
    // Note: View rendering is now automatic due to @Observable.
    // Action-based coordination (PiP updates) is mostly handled in the action methods themselves.

    // We still need to react to isPresenterOverlayActive which changes via engine callback
    // This is set in RecordingState but we need side effects in AppState (WindowManager)
    recordingState.onPresenterOverlayChanged = { [weak self] isActive in
      guard let self else { return }

      if isActive {
        AppLogger.recording.info("⚠️ System Presenter Overlay Active. Hiding App PiP.")
        self.windowManager.forceHidePiPForSystemOverlay()
      } else {
        AppLogger.recording.info("✅ System Presenter Overlay Inactive. Restoring App PiP.")
        self.windowManager.updatePiPState(
          isCameraActive: self.cameraState.isActive,
          isRecording: self.recordingState.isRecording
        )
      }
    }
  }

  private func setupErrorHandling() {
    // NOTE: Error handling is configured in RecordingState.setupRecordingEngine()
    // That handler intelligently filters permission prompts (shows toast instead of alert)
    // and only forwards actual errors to ErrorPresenter.
    //
    // Previously this method overwrote that handler, causing duplicate/incorrect alerts.
    // Now we rely on RecordingState's nuanced error handling.
  }

  // MARK: - Proxy Properties (Backward Compatibility / Convenience)

  var isRecording: Bool { recordingState.isRecording }
  var isPreparing: Bool { recordingState.isPreparing }
  var isPaused: Bool { recordingState.isPaused }
  var isScreenSharing: Bool { windowManager.isScreenSharing }
  var isMicActive: Bool { recordingState.isMicActive }
  var recordingDuration: TimeInterval { recordingState.recordingDuration }

  /// Access to AudioService for microphone selection
  var audioService: AudioService { ServiceContainer.shared.audioService }

  var currentProject: VideoProject? { projectState.currentProject }
  var projects: [VideoProject] { projectState.projects }
  var recentlyAddedClip: VideoClip? { projectState.recentlyAddedClip }
  var showingImportPicker: Bool {
    get { projectState.showingImportPicker }
    set { projectState.showingImportPicker = newValue }
  }

  var screenPreviewLayer: AVSampleBufferDisplayLayer? { recordingState.screenPreviewLayer }

  // MARK: - Actions (Coordinated)
  // Logic extracted to AppState+Actions.swift

  // MARK: - Mode Switching

  func switchToRecording() {
    // DEBUG: Log the switch for diagnostic visibility
    let trace = Thread.callStackSymbols.suffix(10).joined(separator: "\n")
    AppLogger.general.info("🔄 AppState: Switching to RECORDING mode. Stack: \(trace)")

    // CRITICAL: Switch mode IMMEDIATELY for responsive UI
    appMode = .recording

    // Camera operations happen AFTER mode switch
    // cameraEnabled setter automatically starts camera
    if !windowManager.isScreenSharing {
      cameraEnabled = true
    }

    // Start Audio for Metering
    audioService.start()
  }

  func switchToEditing() {
    // CRITICAL: Switch mode IMMEDIATELY for responsive UI
    appMode = .editing

    // Camera cleanup happens AFTER mode switch
    // cameraEnabled setter automatically stops camera
    if !recordingState.isRecording {
      cameraEnabled = false
      audioService.stop()
    }
  }

  // MARK: - Persistence

  func saveCurrentState() {
    guard appMode == .editing, projectState.currentProject != nil else { return }

    let currentScroll = projectState.currentProject?.scrollOffset ?? 0.0
    let currentZoom = projectState.currentProject?.zoomLevel ?? 1.0

    projectState.updatePlaybackState(
      currentTime: playbackState.currentTime.seconds,
      scrollOffset: currentScroll,
      zoomLevel: currentZoom
    )

    AppLogger.general.info(
      "💾 AppState: Saved current state with time: \(playbackState.currentTime.seconds)")
  }
}

//
//  WindowManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
@Observable
class WindowManager {
  // MARK: - Published Properties

  var isPiPVisible = true
  var isScreenSharing = false
  var isTogglingScreenShare = false
  var isTeleprompterVisible = false

  // CRITICAL FIX: Flag to prevent concurrent PiP show/hide operations
  private var isTogglingPiP = false

  // MARK: - Internal Properties

  private var floatingControls: FloatingControlsWindow?
  private var pipWindow: PiPCameraWindow?
  private var teleprompterWindow: TeleprompterWindow?
  private var mainWindowOpener: (@MainActor () -> Void)?

  private var currentPresenterLayout: PresenterOverlayLayout? {
    ServiceContainer.shared.appState.currentProject?.presentationPreset.presenterLayout
  }

  // MARK: - Validation Helpers

  /// Check if a window is valid (not released, has valid window number)
  private func isWindowValid(_ window: NSWindow?) -> Bool {
    guard let window = window else { return false }
    return !window.isReleasedWhenClosed && window.windowNumber > 0
  }

  /// Windows that should be excluded from screen recordings (Controls, PiP Overlay)
  var excludedWindowIDs: [CGWindowID] {
    var ids: [CGWindowID] = []
    // Use helper for cleaner validation
    if isWindowValid(pipWindow), let window = pipWindow {
      ids.append(CGWindowID(window.windowNumber))
    }
    // Note: Controls are now embedded in PiP window, so excluding PiP window ID covers them.
    if isWindowValid(floatingControls), let floating = floatingControls {
      ids.append(CGWindowID(floating.windowNumber))
    }
    if isWindowValid(teleprompterWindow), let teleprompter = teleprompterWindow {
      ids.append(CGWindowID(teleprompter.windowNumber))
    }
    return ids
  }

  /// Get the current PiP window frame for compositing into recordings
  var pipWindowFrame: CGRect? {
    guard isWindowValid(pipWindow), let window = pipWindow, window.isVisible else { return nil }
    return window.frame
  }

  // MARK: - Floating Controls Management

  func showFloatingControls() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }
    if floatingControls == nil {
      AppLogger.window.info("Creating Floating Controls")
      floatingControls = FloatingControlsWindow()
      floatingControls?.makeKeyAndOrderFront(nil)
    }
  }

  func hideFloatingControls() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }
    if floatingControls != nil {
      AppLogger.window.info("Closing Floating Controls")
      floatingControls?.close()
      floatingControls = nil
    }
  }

  // MARK: - PiP Management

  func togglePiPVisibility(isCameraActive: Bool, isRecording: Bool) {
    isPiPVisible.toggle()
    updatePiPState(isCameraActive: isCameraActive, isRecording: isRecording)
  }

  func updatePiPState(isCameraActive: Bool, isRecording _: Bool) {
    let shouldShowPiP = isScreenSharing && isPiPVisible && isCameraActive && currentPresenterLayout != nil
    let shouldShowFloatingControls = isScreenSharing && !shouldShowPiP
    AppLogger.window.info(
      "updatePiPState: isScreenSharing=\(isScreenSharing), isPiPVisible=\(isPiPVisible), isCameraActive=\(isCameraActive), shouldShowPiP=\(shouldShowPiP), shouldShowFloatingControls=\(shouldShowFloatingControls)"
    )

    if shouldShowPiP {
      showPiPWindow()
      hideFloatingControls()
    } else {
      hidePiPWindow()
      if shouldShowFloatingControls {
        showFloatingControls()
      } else {
        hideFloatingControls()
      }
    }
  }

  func forceHidePiPForSystemOverlay() {
    // Hide PiP Camera but SHOW Floating Controls
    hidePiPWindow()
    showFloatingControls()
  }

  private func showPiPWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }

    guard !isTogglingPiP else {
      AppLogger.window.warning("showPiPWindow: Already toggling, ignoring duplicate call")
      return
    }

    isTogglingPiP = true

    // CRITICAL FIX: Validate window state before operations
    if isWindowValid(pipWindow), let existingWindow = pipWindow, existingWindow.isVisible {
      if let layout = currentPresenterLayout {
        existingWindow.applyLayout(layout)
      }
      existingWindow.setupPreview()
      existingWindow.orderFrontRegardless()
      isTogglingPiP = false
      return
    }

    // Create new window if needed
    if pipWindow == nil {
      AppLogger.window.info("Creating PiP Window")
      let newWindow = PiPCameraWindow()
      if newWindow.windowNumber > 0 && !newWindow.isReleasedWhenClosed {
        pipWindow = newWindow
      } else {
        AppLogger.window.error("Failed to create PiP window (invalid window state)")
        ServiceContainer.shared.toastManager.show("Failed to create PiP window", type: .error)
        isTogglingPiP = false
        return
      }
    }

    // CRITICAL FIX: Capture window reference BEFORE async work to prevent race
    guard let window = pipWindow else {
      isTogglingPiP = false
      return
    }

    // CRITICAL FIX: Update filter BEFORE showing window
    // This ensures the PiP is excluded from recording before it becomes visible
    Task { @MainActor in
      // Update filter first
      await updateRecorderFilter()

      // Small delay to ensure filter is applied
      try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

      // NOW show the window (using captured reference)
      // Re-validate window is still valid after async work
      guard !window.isReleasedWhenClosed, window.windowNumber > 0 else {
        isTogglingPiP = false
        return
      }

      if let layout = self.currentPresenterLayout {
        window.applyLayout(layout)
      }
      window.orderFrontRegardless()
      window.showResizeHintIfNeeded()  // Show double-click hint on first use

      isTogglingPiP = false
      AppLogger.window.info("PiP Window shown (filter updated first)")
    }
  }

  private func hidePiPWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }

    guard !isTogglingPiP else {
      AppLogger.window.warning("hidePiPWindow: Already toggling, ignoring duplicate call")
      return
    }

    guard let window = pipWindow else { return }

    isTogglingPiP = true

    AppLogger.window.info("Hiding PiP Window")

    // CRITICAL FIX: Check validity BEFORE any operations
    guard isWindowValid(window) else {
      AppLogger.window.warning("PiP window already released, skipping close")
      pipWindow = nil
      isTogglingPiP = false
      return
    }

    // Nil the reference BEFORE calling close()
    // ARC will deallocate the window when close() completes and no other refs exist
    pipWindow = nil

    // CRITICAL FIX: Do NOT set isReleasedWhenClosed = true here
    // Setting it causes the window to be released immediately during close(),
    // which can crash if the window server is still accessing it.
    // Instead, let ARC handle cleanup naturally.

    // close() is synchronous - handles its own cleanup
    window.close()

    // Reset toggle flag immediately since close() is synchronous
    isTogglingPiP = false
    AppLogger.window.info("PiP Window fully hidden")

    // Update filter
    Task { @MainActor in
      await updateRecorderFilter()
    }

  }

  func toggleScreenShare(isRecording: Bool, isCameraActive: Bool) {
    isScreenSharing.toggle()
    updatePiPState(isCameraActive: isCameraActive, isRecording: isRecording)
  }

  func showTeleprompter() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }

    if !isWindowValid(teleprompterWindow) {
      teleprompterWindow = nil
    }

    if teleprompterWindow == nil {
      AppLogger.window.info("Creating Teleprompter Window")
      teleprompterWindow = TeleprompterWindow()
    }

    guard let window = teleprompterWindow else { return }
    isTeleprompterVisible = true

    Task { @MainActor in
      await updateRecorderFilter()
      try? await Task.sleep(nanoseconds: 50_000_000)

      guard isWindowValid(window) else { return }
      window.orderFrontRegardless()
      window.makeKey()
    }
  }

  func hideTeleprompter() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }

    isTeleprompterVisible = false
    guard let window = teleprompterWindow else { return }

    teleprompterWindow = nil
    window.close()

    Task { @MainActor in
      await updateRecorderFilter()
    }
  }

  // MARK: - App Window Management

  func minimizeMainWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }
    AppLogger.window.info("Attempting to minimize main window...")

    let currentPiPWindow = pipWindow
    let currentFloatingControls = floatingControls
    let windowsSnapshot = NSApp.windows

    // Hide only the main application windows, keeping PiP visible
    for window in windowsSnapshot {
      if window === currentPiPWindow || window === currentFloatingControls {
        AppLogger.window.info("Skipping special window: \(window.title)")
        continue
      }

      AppLogger.window.info("Found window: '\(window.title)' (Visible: \(window.isVisible))")

      if window.isVisible {
        AppLogger.window.info("Ordering out window: '\(window.title)'")
        window.orderOut(nil)
      }
    }

    NSApp.deactivate()
  }

  func restoreMainWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }
    AppLogger.window.info("Restoring main window...")

    NSApp.activate(ignoringOtherApps: true)

    let currentPiPWindow = pipWindow
    let currentFloatingControls = floatingControls
    let windowsSnapshot = NSApp.windows

    var foundMain = false
    var fallbackWindow: NSWindow?
    for window in windowsSnapshot {
      guard !window.isReleasedWhenClosed, window.windowNumber > 0 else {
        continue
      }

      if window === currentPiPWindow || window === currentFloatingControls {
        continue
      }

      let windowClassName = String(describing: type(of: window))
      if windowClassName.contains("PiPCameraWindow")
        || windowClassName.contains("FloatingControlsWindow") {
        continue
      }

      guard window.canBecomeKey else {
        AppLogger.window.info("Skipping window that cannot become key: \(windowClassName)")
        continue
      }

      if fallbackWindow == nil {
        fallbackWindow = window
      }

      if window.title.contains("SaneVideo") || window.title == "SaneVideo" || window.title.isEmpty {
        AppLogger.window.info("Restoring window: '\(window.title)' (ID: \(window.windowNumber))")
        window.makeKeyAndOrderFront(nil)
        foundMain = true
        break
      }
    }

    if !foundMain, let fallbackWindow {
      AppLogger.window.info("Restoring fallback window: '\(fallbackWindow.title)' (ID: \(fallbackWindow.windowNumber))")
      fallbackWindow.makeKeyAndOrderFront(nil)
      foundMain = true
    }

    if !foundMain {
      AppLogger.window.warning("Could not find main window, reopening default window scene")
      NSApp.unhide(nil)
      mainWindowOpener?()
    }
  }

  func registerMainWindowOpener(_ opener: @escaping @MainActor () -> Void) {
    mainWindowOpener = opener
  }

  // MARK: - Cleanup

  func cleanupAllWindows() {
    AppLogger.window.info("Cleaning up all windows before termination...")

    if pipWindow != nil {
      hidePiPWindow()
    }

    hideTeleprompter()
    hideFloatingControls()
    AppLogger.window.info("All windows cleaned up")
  }

  // MARK: - Filter Helpers

  private func updateRecorderFilter() async {
    // CRITICAL FIX: Removed 150ms delay - caller now handles timing
    // The delay was causing PiP to briefly appear in recordings
    if let engine = ServiceContainer.shared.appState.recordingState.engine {
      await engine.screenRecorder.updateContentFilter()
    }
  }
}

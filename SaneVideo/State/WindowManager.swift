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

  // CRITICAL FIX: Flag to prevent concurrent PiP show/hide operations
  private var isTogglingPiP = false

  // MARK: - Internal Properties

  private var floatingControls: FloatingControlsWindow?
  private var pipWindow: PiPCameraWindow?

  /// Windows that should be excluded from screen recordings (Controls, PiP Overlay)
  var excludedWindowIDs: [CGWindowID] {
    var ids: [CGWindowID] = []
    // CRITICAL FIX: Store reference and validate before accessing properties
    if let window = pipWindow,
       !window.isReleasedWhenClosed,
       window.windowNumber > 0 {
      ids.append(CGWindowID(window.windowNumber))
    }
    // Note: Controls are now embedded in PiP window, so excluding PiP window ID covers them.

    if let floating = floatingControls,
       !floating.isReleasedWhenClosed,
       floating.windowNumber > 0 {
      ids.append(CGWindowID(floating.windowNumber))
    }
    return ids
  }

  /// Get the current PiP window frame for compositing into recordings
  var pipWindowFrame: CGRect? {
    guard let window = pipWindow else { return nil }
    guard !window.isReleasedWhenClosed, window.isVisible else { return nil }
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

  func updatePiPState(isCameraActive _: Bool, isRecording _: Bool) {
    let shouldShowPiP = isScreenSharing && isPiPVisible
    AppLogger.window.info(
      "updatePiPState: isScreenSharing=\(isScreenSharing), isPiPVisible=\(isPiPVisible), shouldShow=\(shouldShowPiP)"
    )

    if shouldShowPiP {
      showPiPWindow()
    } else {
      hidePiPWindow()
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
    defer { isTogglingPiP = false }

    // CRITICAL FIX: Validate window state before operations
    if let existingWindow = pipWindow,
       existingWindow.isVisible,
       !existingWindow.isReleasedWhenClosed,
       existingWindow.windowNumber > 0 {
      existingWindow.setupPreview()
      existingWindow.orderFrontRegardless()
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
        return
      }
    }

    pipWindow?.orderFrontRegardless()
    pipWindow?.snapToCorner(.bottomRight)

    // Controls are embedded and shown automatically with the window.

    // Update Screen Recorder filter
    Task { @MainActor in
      await updateRecorderFilter()
    }
  }

  private func hidePiPWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }

    guard !isTogglingPiP else {
      AppLogger.window.warning("hidePiPWindow: Already toggling, ignoring duplicate call")
      return
    }

    isTogglingPiP = true
    defer { isTogglingPiP = false }

    guard let window = pipWindow else { return }

    AppLogger.window.info("Hiding PiP Window")

    pipWindow = nil

    // Close PiP window itself
    let windowIsValid = !window.isReleasedWhenClosed && window.windowNumber > 0
    if windowIsValid {
      window.orderOut(nil)
      window.isReleasedWhenClosed = true
      window.close()
    } else {
      AppLogger.window.warning("PiP window already released, skipping close")
    }

    // Update filter
    Task { @MainActor in
      await updateRecorderFilter()
    }

    hideFloatingControls()

    AppLogger.window.info("PiP Window fully hidden")
  }

  func toggleScreenShare(isRecording: Bool, isCameraActive: Bool) {
    isScreenSharing.toggle()
    updatePiPState(isCameraActive: isCameraActive, isRecording: isRecording)
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

      if window.title.contains("SaneVideo") || window.title == "SaneVideo" || window.title.isEmpty {
        AppLogger.window.info("Restoring window: '\(window.title)' (ID: \(window.windowNumber))")
        window.makeKeyAndOrderFront(nil)
        foundMain = true
        break
      }
    }

    if !foundMain {
      AppLogger.window.warning("Could not find specific main window, calling unhide")
      NSApp.unhide(nil)
    }
  }

  // MARK: - Cleanup

  func cleanupAllWindows() {
    AppLogger.window.info("Cleaning up all windows before termination...")

    if pipWindow != nil {
      hidePiPWindow()
    }

    hideFloatingControls()
    AppLogger.window.info("All windows cleaned up")
  }

  // MARK: - Filter Helpers

  private func updateRecorderFilter() async {
    try? await Task.sleep(nanoseconds: 150_000_000)

    if let engine = ServiceContainer.shared.appState.recordingState.engine {
      await engine.screenRecorder.updateContentFilter()
    }
  }
}

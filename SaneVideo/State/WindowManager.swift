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

  // CRITICAL FIX: Flag to prevent concurrent screen share toggles
  var isTogglingScreenShare = false

  // MARK: - Internal Properties

  private var floatingControls: FloatingControlsWindow?
  private var pipWindow: PiPCameraWindow?

  /// Windows that should be excluded from screen recordings (Controls, PiP Overlay)
  var excludedWindowIDs: [CGWindowID] {
    var ids: [CGWindowID] = []
    // CRITICAL FIX: Store reference to prevent zombie access
    if let window = pipWindow, let controls = window.controlsWindow {
      ids.append(CGWindowID(controls.windowNumber))
    }
    if let floating = floatingControls {
      ids.append(CGWindowID(floating.windowNumber))
    }
    return ids
  }

  /// Get the current PiP window frame for compositing into recordings
  var pipWindowFrame: CGRect? {
    // CRITICAL FIX: Store reference and check visibility safely
    guard let window = pipWindow else { return nil }
    // CRITICAL FIX: Check if window is still valid before accessing properties
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
    // @MainActor ensures we're already on main thread
    isPiPVisible.toggle()
    updatePiPState(isCameraActive: isCameraActive, isRecording: isRecording)
  }

  func updatePiPState(isCameraActive _: Bool, isRecording _: Bool) {
    // @MainActor ensures we're already on main thread
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
    // UX IMPROVEMENT: Keep floating controls visible as a backup.
    // This ensures the user always has a "Record" button even if they start Screen Share before Recording.
    showFloatingControls()

    // @MainActor ensures we're already on main thread

    // Check if window exists and is visible
    if let existingWindow = pipWindow, existingWindow.isVisible {
      existingWindow.setupPreview()
      // CRITICAL FIX: Ensure controls window is visible even if PiP already exists
      if let controls = existingWindow.controlsWindow {
        controls.orderFrontRegardless()
        controls.level = .floating
        controls.hidesOnDeactivate = false
      }
      return
    }

    // Create new window if needed
    if pipWindow == nil {
      AppLogger.window.info("Creating PiP Window")
      pipWindow = PiPCameraWindow()
    }

    pipWindow?.orderFrontRegardless()
    pipWindow?.snapToCorner(.bottomRight)

    // CRITICAL FIX: Ensure controls window is visible and on top
    if let controls = pipWindow?.controlsWindow {
      controls.orderFrontRegardless()
      controls.level = .floating
      controls.hidesOnDeactivate = false
    }

    // Update Screen Recorder filter
    Task { @MainActor in
      await updateRecorderFilter()
    }
  }

  private func hidePiPWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }
    // @MainActor ensures we're already on main thread

    // Prevent re-entry if already cleaning up
    guard let window = pipWindow else { return }

    AppLogger.window.info("Hiding PiP Window")

    // CRITICAL FIX: Store all references before any operations
    // Access controlsWindow BEFORE clearing pipWindow to prevent zombie access
    let controls = window.controlsWindow

    // CRITICAL FIX: Clear reference IMMEDIATELY to prevent re-entry
    // But we've already stored the window and controls references
    pipWindow = nil

    // CRITICAL FIX: Remove child window relationship while parent is still valid
    // Check window validity before accessing - use multiple safety checks
    if let controls = controls {
      // Verify window is still valid by checking multiple properties
      let windowIsValid = !window.isReleasedWhenClosed && window.windowNumber > 0

      if windowIsValid {
        AppLogger.window.info("Closing PiP Controls Window")
        // Remove parent-child relationship while window is still valid
        window.removeChildWindow(controls)
      }

      // Always close controls, even if parent window is invalid
      // Use safe access pattern
      if !controls.isReleasedWhenClosed {
        controls.orderOut(nil)
        controls.isReleasedWhenClosed = true
        controls.close()
      }
    }

    // CRITICAL FIX: Close PiP window itself
    // Check if window is still valid before closing - use multiple safety checks
    let windowIsValid = !window.isReleasedWhenClosed && window.windowNumber > 0
    if windowIsValid {
      window.orderOut(nil)
      window.isReleasedWhenClosed = true
      window.close()
    } else {
      AppLogger.window.warning("PiP window already released, skipping close")
    }

    // CRITICAL FIX: Also hide floating controls when PiP is hidden
    // (They were shown as backup when PiP was shown, but should go away when returning to main app)
    hideFloatingControls()

    // Update Screen Recorder filter to remove window
    // Use Task to avoid blocking, but ensure it's safe
    Task { @MainActor in
      await updateRecorderFilter()
    }

    AppLogger.window.info("PiP Window and controls fully hidden")
  }

  func toggleScreenShare(isRecording: Bool, isCameraActive: Bool) {
    // @MainActor ensures we're already on main thread
    isScreenSharing.toggle()
    updatePiPState(isCameraActive: isCameraActive, isRecording: isRecording)
  }

  // MARK: - App Window Management

  func minimizeMainWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }
    // @MainActor ensures we're already on main thread
    AppLogger.window.info("Attempting to minimize main window...")

    // CRITICAL FIX: Store references before iteration to prevent zombie access
    let currentPiPWindow = pipWindow
    let currentFloatingControls = floatingControls

    // CRITICAL FIX: Create snapshot to prevent iteration issues
    let windowsSnapshot = NSApp.windows

    // Hide only the main application windows, keeping PiP visible
    for window in windowsSnapshot {
      // CRITICAL FIX: Use reference equality to prevent zombie access
      if window === currentPiPWindow || window === currentFloatingControls {
        AppLogger.window.info("Skipping special window: \(window.title)")
        continue
      }

      AppLogger.window.info("Found window: '\(window.title)' (Visible: \(window.isVisible))")

      // Only hide standard windows
      if window.isVisible {
        AppLogger.window.info("Ordering out window: '\(window.title)'")
        window.orderOut(nil)
      }
    }

    // Deactivate app to let user interact with the screen behind
    NSApp.deactivate()
  }

  func restoreMainWindow() {
    if TestEnvironment.isTesting && !TestEnvironment.isUITesting { return }
    // @MainActor ensures we're already on main thread
    AppLogger.window.info("Restoring main window...")

    // Bring app back to front
    NSApp.activate(ignoringOtherApps: true)

    // CRITICAL FIX: Store pipWindow reference to safely check against it
    let currentPiPWindow = pipWindow
    let currentFloatingControls = floatingControls

    // CRITICAL FIX: Create a snapshot of windows array to prevent iteration issues
    // NSApp.windows can change during iteration, causing crashes
    let windowsSnapshot = NSApp.windows

    // Find and show main window
    var foundMain = false
    for window in windowsSnapshot {
      // CRITICAL FIX: Use reference equality instead of type checking to prevent zombie access
      // Type checking on deallocated windows can cause crashes
      if window === currentPiPWindow || window === currentFloatingControls {
        continue
      }

      // CRITICAL FIX: Also check by window class name safely
      let windowClassName = String(describing: type(of: window))
      if windowClassName.contains("PiPCameraWindow")
        || windowClassName.contains("PiPControlsWindow")
        || windowClassName.contains("FloatingControlsWindow") {
        continue
      }

      // UI TEST FIX: Exclude windows that cannot become key (like NSStatusBarWindow)
      // This prevents "failed to become key" warnings and ensures the REAL main window gets focus.
      guard window.canBecomeKey else {
        AppLogger.window.info("Skipping window that cannot become key: \(windowClassName)")
        continue
      }

      // Heuristic: If it has a title and is not special, it's likely our main window
      // Also accept empty titles (since we set navigationTitle("") in Rec mode)
      // Or identifying if it's the MainWindow class (if applicable) or just the first robust window
      if window.title.contains("SaneVideo") || window.title == "SaneVideo" || window.title.isEmpty {
        AppLogger.window.info("Restoring window: '\(window.title)' (ID: \(window.windowNumber))")
        window.makeKeyAndOrderFront(nil)
        foundMain = true
        break
      }
    }

    if !foundMain {
      // Fallback
      AppLogger.window.warning("Could not find specific main window, calling unhide")
      NSApp.unhide(nil)
    }
  }

  // MARK: - Filter Helpers

  private func updateRecorderFilter() async {
    // Fix: Add slight delay to allow Window Server to register the new window state.
    // In Tahoe, 150ms is usually sufficient for currentProcess to see the change.
    try? await Task.sleep(nanoseconds: 150_000_000)

    // Access screenRecorder via AppState -> RecordingState -> engine
    // CRITICAL FIX: Check if engine and screenRecorder exist before accessing
    if let engine = ServiceContainer.shared.appState.recordingState.engine {
      await engine.screenRecorder.updateContentFilter()
    }
  }
}

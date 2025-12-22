//
//  WindowManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation
import AppKit
import Combine
import SwiftUI

@MainActor
@Observable
class WindowManager {
    // MARK: - Published Properties

    var isPiPVisible = true
    var isScreenSharing = false

    // MARK: - Internal Properties

    private var floatingControls: FloatingControlsWindow?
    private var pipWindow: PiPCameraWindow?

    /// Windows that should be excluded from screen recordings (Controls, PiP Overlay)
    var excludedWindowIDs: [CGWindowID] {
        var ids: [CGWindowID] = []
        if let controls = pipWindow?.controlsWindow {
            ids.append(CGWindowID(controls.windowNumber))
        }
        if let floating = floatingControls {
            ids.append(CGWindowID(floating.windowNumber))
        }
        return ids
    }

    // MARK: - Floating Controls Management

    func showFloatingControls() {
        if floatingControls == nil {
            AppLogger.window.info("Creating Floating Controls")
            floatingControls = FloatingControlsWindow()
            floatingControls?.makeKeyAndOrderFront(nil)
        }
    }

    func hideFloatingControls() {
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
        AppLogger.window.info("updatePiPState: isScreenSharing=\(isScreenSharing), isPiPVisible=\(isPiPVisible), shouldShow=\(shouldShowPiP)")

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
        // UX IMPROVEMENT: Keep floating controls visible as a backup.
        // This ensures the user always has a "Record" button even if they start Screen Share before Recording.
        showFloatingControls()
        
        // @MainActor ensures we're already on main thread
        
        // Check if window exists and is visible
        if let existingWindow = pipWindow, existingWindow.isVisible {
            existingWindow.setupPreview()
            return
        }

        // Create new window if needed
        if pipWindow == nil {
            AppLogger.window.info("Creating PiP Window")
            pipWindow = PiPCameraWindow()
        }

        pipWindow?.orderFrontRegardless()
        pipWindow?.snapToCorner(.bottomRight)
    }

    private func hidePiPWindow() {
        // @MainActor ensures we're already on main thread
        
        // Prevent re-entry if already cleaning up
        guard let window = pipWindow else { return }
        
        AppLogger.window.info("Hiding PiP Window")

        // Force break parent-child relationship in AppKit to avoid zombie access
        if let controls = window.controlsWindow {
            window.removeChildWindow(controls)
            controls.close()
        }
        
        window.orderOut(nil)
        window.close()
        pipWindow = nil
    }

    func toggleScreenShare(isRecording: Bool, isCameraActive: Bool) {
        // @MainActor ensures we're already on main thread
        isScreenSharing.toggle()
        updatePiPState(isCameraActive: isCameraActive, isRecording: isRecording)
    }

    // MARK: - App Window Management

    func minimizeMainWindow() {
        // @MainActor ensures we're already on main thread
        AppLogger.window.info("Attempting to minimize main window...")

        // Hide only the main application windows, keeping PiP visible
        for window in NSApp.windows {
            // Skip our special windows
            if window === pipWindow || window === floatingControls {
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
        // @MainActor ensures we're already on main thread
        AppLogger.window.info("Restoring main window...")

        // Bring app back to front
        NSApp.activate(ignoringOtherApps: true)

        // Find and show main window
        var foundMain = false
        for window in NSApp.windows {
            // CRITICAL FIX: Explicitly exclude PiP classes to prevent zombie access
            if window is PiPCameraWindow || window is PiPControlsWindow || window is FloatingControlsWindow {
                 continue
            }
            
            // UI TEST FIX: Exclude windows that cannot become key (like NSStatusBarWindow)
            // This prevents "failed to become key" warnings and ensures the REAL main window gets focus.
            guard window.canBecomeKey else {
                AppLogger.window.info("Skipping window that cannot become key: \(type(of: window))")
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
}

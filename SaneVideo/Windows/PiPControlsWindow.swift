//
//  PiPControlsWindow.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AppKit
import SwiftUI

/// A separate window for PiP controls that floats above the camera window.
/// This separation allows the controls to be excluded from screen recordings
/// while keeping the camera feed visible.
final class PiPControlsWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  init(frame: NSRect) {
    // Initialize with same frame as parent, but we will constrain content
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    title = "SaneVideo PiP Controls"  // Critical for ScreenRecorder filtering
    setupWindow()
  }

  private func setupWindow() {
    isReleasedWhenClosed = false
    level = .floating  // CRITICAL FIX: Match parent PiP level (.floating) to stay visible
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false  // Controls view has its own shadow/background
    ignoresMouseEvents = false
    hidesOnDeactivate = false  // CRITICAL FIX: Keep visible when app loses focus
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    // Accessibility: Ensure controls are findable by UI tests
    setAccessibilityElement(true)
    setAccessibilityRole(.window)
    setAccessibilitySubrole(.floatingWindow)
    setAccessibilityIdentifier("PiPControlsWindow")

    // Exclude from screen capture (macOS 11+)
    if #available(macOS 11.0, *) {
      self.sharingType = .none
    }

    // Ensure transparency
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    // Use PassThroughView as content view to allow clicks to fall through to parent
    let passThroughView = PassThroughView(frame: contentRect(forFrameRect: frame))
    passThroughView.autoresizingMask = [.width, .height]
    self.contentView = passThroughView

    // Setup Content
    let controlsView = PiPControlsView()
    let hostingView = NSHostingView(
      rootView: controlsView.environment(ServiceContainer.shared.appState))
    hostingView.translatesAutoresizingMaskIntoConstraints = false

    passThroughView.addSubview(hostingView)

    // Constrain to bottom center
    NSLayoutConstraint.activate([
      hostingView.bottomAnchor.constraint(equalTo: passThroughView.bottomAnchor, constant: -8),
      hostingView.centerXAnchor.constraint(equalTo: passThroughView.centerXAnchor),
      hostingView.heightAnchor.constraint(equalToConstant: 36),
    ])
  }
}

// Custom view that lets clicks pass through unless they hit a subview (like a button)
private class PassThroughView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    // Convert point to view coordinate system
    let pointInView = convert(point, from: nil)

    // Check if we hit any subview (buttons)
    // We iterate in reverse to check top-most views first
    for subview in subviews.reversed() {
      // Basic hit test on subview
      if subview.frame.contains(pointInView), !subview.isHidden {
        // Recursively check subview
        if let hit = subview.hitTest(point) {
          return hit
        }
      }
    }

    // If no subview was hit, return nil to let event pass through to window/window below
    return nil
  }
}

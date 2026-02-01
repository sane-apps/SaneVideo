//
//  ClickTrackingService.swift
//  SaneVideo
//
//  Tracks mouse clicks and continuous cursor movement during recording.
//  Click data powers auto-zoom; cursor data enables spring-smoothed viewport following.
//

import AppKit
import CoreGraphics
import Foundation

/// Service to track and save mouse click and cursor movement events
actor ClickTrackingService {

    private var isTracking = false
    private var clicks: [ClickSample] = []
    private var cursorSamples: [CursorSample] = []
    private var startTime: Date?
    nonisolated(unsafe) private var clickMonitor: Any?
    nonisolated(unsafe) private var moveMonitor: Any?

    // Screen size for normalization
    private var screenSize: CGSize = .zero

    // Button state tracking for cursor samples
    private var isButtonDown = false
    private var activeButton: Int = 0

    // Throttle: minimum interval between cursor samples (16ms ≈ 60fps)
    private var lastCursorSampleTime: TimeInterval = 0
    private static let cursorSampleInterval: TimeInterval = 1.0 / 60.0

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        clicks = []
        cursorSamples = []
        startTime = Date()
        lastCursorSampleTime = 0
        isButtonDown = false
        activeButton = 0

        // Get main screen size
        if let screen = NSScreen.main {
            screenSize = screen.frame.size
        } else {
            screenSize = CGSize(width: 1920, height: 1080)
        }

        Task { @MainActor in
            // Click monitor (existing behavior)
            let cMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]
            ) { [weak self] event in
                Task {
                    await self?.handleClickEvent(event)
                }
            }
            self.clickMonitor = cMonitor

            // Cursor movement monitor (new: tracks mouseMoved + drag)
            let mMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] event in
                Task {
                    await self?.handleCursorMoveEvent(event)
                }
            }
            self.moveMonitor = mMonitor

            if cMonitor != nil && mMonitor != nil {
                AppLogger.recording.info("ClickTrackingService: Started tracking clicks + cursor movement")
            } else {
                AppLogger.recording.warning("ClickTrackingService: Failed to create event monitors - may need accessibility permissions")
            }
        }
    }

    func stopTrackingAndSave(to url: URL) async throws -> URL? {
        guard isTracking else { return nil }

        isTracking = false

        // Remove event monitors (must be done on MainActor)
        let cMon = self.clickMonitor
        let mMon = self.moveMonitor
        Task { @MainActor in
            if let cMon { NSEvent.removeMonitor(cMon) }
            if let mMon { NSEvent.removeMonitor(mMon) }
        }
        self.clickMonitor = nil
        self.moveMonitor = nil

        let encoder = JSONEncoder()

        // Save clicks to JSON file
        let clicksURL = url.deletingPathExtension().appendingPathExtension("clicks.json")
        let clicksData = try encoder.encode(clicks)
        try clicksData.write(to: clicksURL)

        // Save cursor path to JSON file
        var cursorURL: URL?
        if !cursorSamples.isEmpty {
            let cURL = url.deletingPathExtension().appendingPathExtension("cursor.json")
            let cursorData = try encoder.encode(cursorSamples)
            try cursorData.write(to: cURL)
            cursorURL = cURL
            AppLogger.recording.info("ClickTrackingService: Saved \(cursorSamples.count) cursor samples to \(cURL.lastPathComponent)")
        }

        AppLogger.recording.info("ClickTrackingService: Saved \(clicks.count) click events to \(clicksURL.lastPathComponent)")

        // Return clicks URL for backward compatibility
        _ = cursorURL
        return clicksURL
    }

    private func handleClickEvent(_ event: NSEvent) async {
        guard let startTime else { return }

        let location = await MainActor.run {
            NSEvent.mouseLocation
        }

        let normalizedX = location.x / screenSize.width
        let normalizedY = 1.0 - (location.y / screenSize.height)
        let timestamp = Date().timeIntervalSince(startTime)

        let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown
        let button = (event.type == .leftMouseDown || event.type == .leftMouseUp) ? 0 : 1

        // Update button state for cursor samples
        isButtonDown = isDown
        activeButton = button

        if isDown {
            let click = ClickSample(
                timestamp: timestamp,
                x: Double(normalizedX),
                y: Double(normalizedY),
                button: button
            )
            clicks.append(click)

            AppLogger.recording.debug("ClickTrackingService: Click at (\(String(format: "%.2f", normalizedX)), \(String(format: "%.2f", normalizedY))) at \(String(format: "%.2f", timestamp))s")
        }

        // Also record a cursor sample at click time for precise alignment
        let cursorSample = CursorSample(
            timestamp: timestamp,
            x: Double(normalizedX),
            y: Double(normalizedY),
            isDown: isDown,
            button: button
        )
        cursorSamples.append(cursorSample)
        lastCursorSampleTime = timestamp
    }

    private func handleCursorMoveEvent(_: NSEvent) async {
        guard let startTime else { return }

        let timestamp = Date().timeIntervalSince(startTime)

        // Throttle to ~60fps
        guard timestamp - lastCursorSampleTime >= Self.cursorSampleInterval else { return }

        let location = await MainActor.run {
            NSEvent.mouseLocation
        }

        let normalizedX = location.x / screenSize.width
        let normalizedY = 1.0 - (location.y / screenSize.height)

        let sample = CursorSample(
            timestamp: timestamp,
            x: Double(normalizedX),
            y: Double(normalizedY),
            isDown: isButtonDown,
            button: activeButton
        )
        cursorSamples.append(sample)
        lastCursorSampleTime = timestamp
    }

    /// Get all recorded clicks
    func getClicks() -> [ClickSample] {
        return clicks
    }

    /// Get all recorded cursor samples
    func getCursorSamples() -> [CursorSample] {
        return cursorSamples
    }
}

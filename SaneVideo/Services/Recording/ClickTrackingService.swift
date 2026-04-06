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
    private var keystrokeSamples: [KeystrokeSample] = []
    private var startTime: Date?
    nonisolated(unsafe) private var clickMonitor: Any?
    nonisolated(unsafe) private var moveMonitor: Any?
    nonisolated(unsafe) private var keyMonitor: Any?

    // Screen size for normalization
    private var screenSize: CGSize = .zero

    // Button state tracking for cursor samples
    private var isButtonDown = false
    private var activeButton: Int = 0

    // Throttle: minimum interval between cursor samples (16ms ≈ 60fps)
    private var lastCursorSampleTime: TimeInterval = 0
    private static let cursorSampleInterval: TimeInterval = 1.0 / 60.0
    private static let navigationKeyCodes: Set<UInt16> = [36, 48, 49, 51, 53, 123, 124, 125, 126]

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        clicks = []
        cursorSamples = []
        keystrokeSamples = []
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
                let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown
                let button = (event.type == .leftMouseDown || event.type == .leftMouseUp) ? 0 : 1
                Task { [weak self] in
                    await self?.handleClickEvent(isDown: isDown, button: button)
                }
            }
            self.clickMonitor = cMonitor

            // Cursor movement monitor (new: tracks mouseMoved + drag)
            let mMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] _ in
                Task { [weak self] in
                    await self?.handleCursorMoveEvent()
                }
            }
            self.moveMonitor = mMonitor

            // Capture shortcuts and navigation keys only to avoid storing free-form typing.
            let kMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.keyDown]
            ) { [weak self] event in
                let key = event.charactersIgnoringModifiers ?? ""
                let modifierFlags = event.modifierFlags.rawValue
                let keyCode = event.keyCode
                Task { [weak self] in
                    await self?.handleKeyEvent(
                        key: key,
                        modifierFlags: modifierFlags,
                        keyCode: keyCode
                    )
                }
            }
            self.keyMonitor = kMonitor

            if cMonitor == nil {
                AppLogger.recording.warning("ClickTrackingService: Failed to create event monitors - may need accessibility permissions")
            } else if mMonitor == nil {
                AppLogger.recording.warning("ClickTrackingService: Failed to create event monitors - may need accessibility permissions")
            } else if kMonitor == nil {
                AppLogger.recording.warning("ClickTrackingService: Failed to create event monitors - may need accessibility permissions")
            } else {
                AppLogger.recording.info("ClickTrackingService: Started tracking clicks, cursor movement, and shortcut keys")
            }
        }
    }

    func stopTrackingAndSave(to url: URL) async throws -> URL? {
        guard isTracking else { return nil }

        isTracking = false

        // Remove event monitors (must be done on MainActor)
        nonisolated(unsafe) let cMon = self.clickMonitor
        nonisolated(unsafe) let mMon = self.moveMonitor
        nonisolated(unsafe) let kMon = self.keyMonitor
        await MainActor.run {
            if let cMon = cMon { NSEvent.removeMonitor(cMon) }
            if let mMon = mMon { NSEvent.removeMonitor(mMon) }
            if let kMon = kMon { NSEvent.removeMonitor(kMon) }
        }
        self.clickMonitor = nil
        self.moveMonitor = nil
        self.keyMonitor = nil

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

        if !keystrokeSamples.isEmpty {
            let keysURL = url.deletingPathExtension().appendingPathExtension("keys.json")
            let keyData = try encoder.encode(keystrokeSamples)
            try keyData.write(to: keysURL)
            AppLogger.recording.info("ClickTrackingService: Saved \(keystrokeSamples.count) shortcut key samples to \(keysURL.lastPathComponent)")
        }

        AppLogger.recording.info("ClickTrackingService: Saved \(clicks.count) click events to \(clicksURL.lastPathComponent)")

        // Return clicks URL for backward compatibility
        _ = cursorURL
        return clicksURL
    }

    private func handleClickEvent(isDown: Bool, button: Int) async {
        guard let startTime else { return }

        let location = await MainActor.run {
            NSEvent.mouseLocation
        }

        let normalizedX = location.x / screenSize.width
        let normalizedY = 1.0 - (location.y / screenSize.height)
        let timestamp = Date().timeIntervalSince(startTime)

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

    private func handleCursorMoveEvent() async {
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

    private func handleKeyEvent(key: String, modifierFlags: NSEvent.ModifierFlags.RawValue, keyCode: UInt16) async {
        guard let startTime else { return }

        let normalizedKey = normalizedKey(key: key, keyCode: keyCode)
        let modifiers = modifierLabels(for: NSEvent.ModifierFlags(rawValue: modifierFlags))
        guard shouldCaptureKey(key: normalizedKey, modifiers: modifiers, keyCode: keyCode) else { return }

        let sample = KeystrokeSample(
            timestamp: Date().timeIntervalSince(startTime),
            key: normalizedKey,
            modifiers: modifiers,
            keyCode: keyCode
        )
        keystrokeSamples.append(sample)
    }

    private func shouldCaptureKey(key: String, modifiers: [String], keyCode: UInt16) -> Bool {
        if Self.navigationKeyCodes.contains(keyCode) {
            return true
        }

        if !modifiers.isEmpty {
            return !key.isEmpty
        }

        return false
    }

    private func normalizedKey(key: String, keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default:
            return key
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }
    }

    private func modifierLabels(for flags: NSEvent.ModifierFlags) -> [String] {
        let filtered = flags.intersection(.deviceIndependentFlagsMask)
        var labels: [String] = []

        if filtered.contains(.command) { labels.append("Command") }
        if filtered.contains(.shift) { labels.append("Shift") }
        if filtered.contains(.option) { labels.append("Option") }
        if filtered.contains(.control) { labels.append("Control") }
        if filtered.contains(.function) { labels.append("Fn") }

        return labels
    }

    /// Get all recorded clicks
    func getClicks() -> [ClickSample] {
        return clicks
    }

    /// Get all recorded cursor samples
    func getCursorSamples() -> [CursorSample] {
        return cursorSamples
    }

    /// Get locally recorded shortcut/navigation keys
    func getKeystrokeSamples() -> [KeystrokeSample] {
        return keystrokeSamples
    }
}

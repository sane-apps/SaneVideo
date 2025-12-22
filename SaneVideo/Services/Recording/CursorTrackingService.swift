//
//  CursorTrackingService.swift
//  SaneVideo
//
//  Tracks mouse cursor position during recording for post-production effects.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

// CursorSample is defined in VideoClip.swift or CursorSample.swift (Core/Models)

/// Service to track and save cursor movements
actor CursorTrackingService {

    private var isTracking = false
    private var samples: [CursorSample] = []
    private var startTime: Date?
    private var monitor: Any?

    // Sampling rate (e.g., 60Hz = ~0.016s)
    // We can use a timer or just event monitoring. Event monitoring is more accurate for movement.
    // But we might want to sample at fixed intervals to reduce data size and easier playback.
    // Let's use a Timer for consistent sampling.
    private var timer: Timer?

    // Screen size for normalization
    private var screenSize: CGSize = .zero

    private var trackingTask: Task<Void, Never>?

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        samples = []
        startTime = Date()

        // Get main screen size
        if let screen = NSScreen.main {
            screenSize = screen.frame.size
        } else {
            screenSize = CGSize(width: 1920, height: 1080)
        }

        // Start sampling task (30fps)
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.captureSample()
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000 / 30)
                } catch {
                    break
                }
            }
        }
    }

    func stopTrackingAndSave(to url: URL) async throws -> URL? {
        guard isTracking else { return nil }

        trackingTask?.cancel()
        trackingTask = nil
        isTracking = false
        monitor = nil

        let fileURL = url.deletingPathExtension().appendingPathExtension("json")

        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(samples)
        try data.write(to: fileURL)

        return fileURL
    }

    private func captureSample() async {
        guard let startTime = startTime else { return }

        // Get current mouse location (global)
        // NSEvent.mouseLocation is theoretically safe but we are fixing a MainActor init issue anyway
        let location = await MainActor.run { NSEvent.mouseLocation }

        // Normalize
        let normalizedX = location.x / screenSize.width
        let normalizedY = location.y / screenSize.height

        let timestamp = Date().timeIntervalSince(startTime)

        // Create sample
        let sample = CursorSample(timestamp: timestamp, x: Double(normalizedX), y: Double(normalizedY))

        samples.append(sample)
    }
}

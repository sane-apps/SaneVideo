//
//  ClickTrackingService.swift
//  SaneVideo
//
//  Tracks mouse clicks during recording for auto-zoom feature
//  Similar to CursorTrackingService but captures click events
//

import AppKit
import CoreGraphics
import Foundation

/// Service to track and save mouse click events
actor ClickTrackingService {
    
    private var isTracking = false
    private var clicks: [ClickSample] = []
    private var startTime: Date?
    nonisolated(unsafe) private var eventMonitor: Any?
    
    // Screen size for normalization
    private var screenSize: CGSize = .zero
    
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        clicks = []
        startTime = Date()
        
        // Get main screen size
        if let screen = NSScreen.main {
            screenSize = screen.frame.size
        } else {
            screenSize = CGSize(width: 1920, height: 1080)
        }
        
        // Use NSEvent global monitor for click tracking
        // Simpler than CGEventTap and works well for our use case
        Task { @MainActor in
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                Task {
                    await self?.handleClickEvent(event)
                }
            }
            
            // Store monitor (nonisolated, safe because we only access from MainActor)
            self.eventMonitor = monitor
            
            if monitor != nil {
                AppLogger.recording.info("ClickTrackingService: Started tracking mouse clicks (NSEvent global monitor)")
            } else {
                AppLogger.recording.warning("ClickTrackingService: Failed to create event monitor - may need accessibility permissions")
            }
        }
    }
    
    func stopTrackingAndSave(to url: URL) async throws -> URL? {
        guard isTracking else { return nil }
        
        isTracking = false
        
        // Remove event monitor (must be done on MainActor)
        let monitor = self.eventMonitor
        if let monitor = monitor {
            Task { @MainActor in
                NSEvent.removeMonitor(monitor)
            }
        }
        self.eventMonitor = nil
        
        // Save clicks to JSON file
        let fileURL = url.deletingPathExtension().appendingPathExtension("clicks.json")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(clicks)
        try data.write(to: fileURL)
        
        AppLogger.recording.info("ClickTrackingService: Saved \(clicks.count) click events to \(fileURL.lastPathComponent)")
        
        return fileURL
    }
    
    private func handleClickEvent(_ event: NSEvent) async {
        guard let startTime = startTime else { return }
        
        // Get click location (screen coordinates)
        // For global monitor events, NSEvent.mouseLocation gives screen coordinates
        // macOS uses bottom-left origin, we need top-left for our normalized system
        let location = await MainActor.run { 
            NSEvent.mouseLocation
        }
        
        // Normalize coordinates (0-1)
        // NSEvent.mouseLocation uses bottom-left origin, we need top-left
        let screenHeight = screenSize.height
        let normalizedX = location.x / screenSize.width
        let normalizedY = 1.0 - (location.y / screenHeight)  // Flip Y for top-left origin
        
        // Calculate timestamp relative to recording start
        let timestamp = Date().timeIntervalSince(startTime)
        
        // Determine button (0 = left, 1 = right)
        let button = event.type == .leftMouseDown ? 0 : 1
        
        // Create click sample
        let click = ClickSample(
            timestamp: timestamp,
            x: Double(normalizedX),
            y: Double(normalizedY),
            button: button
        )
        
        clicks.append(click)
        
        AppLogger.recording.debug("ClickTrackingService: Recorded click at (\(String(format: "%.2f", normalizedX)), \(String(format: "%.2f", normalizedY))) at \(String(format: "%.2f", timestamp))s")
    }
    
    /// Get all recorded clicks
    func getClicks() -> [ClickSample] {
        return clicks
    }
}

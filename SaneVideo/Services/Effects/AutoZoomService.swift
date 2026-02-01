//
//  AutoZoomService.swift
//  SaneVideo
//
//  Generates automatic zoom keyframes from mouse click events
//  Screen Studio style: zooms in on click locations with smooth camera movement
//

import AVFoundation
import CoreMedia
import Foundation

/// Service to generate auto-zoom keyframes from click events
@MainActor
class AutoZoomService {
    
    /// Configuration for auto-zoom behavior
    struct AutoZoomConfig {
        var zoomScale: Double = 1.5  // How much to zoom (1.5x = 50% zoom)
        var zoomDuration: TimeInterval = 0.5  // How long to zoom in (seconds)
        var holdDuration: TimeInterval = 1.0  // How long to hold zoom (seconds)
        var zoomOutDuration: TimeInterval = 0.5  // How long to zoom out (seconds)
        var minTimeBetweenZooms: TimeInterval = 0.3  // Minimum time between zooms (prevent rapid-fire)
        var easeInOut: Bool = true  // Use smooth easing
        
        static let `default` = AutoZoomConfig()
    }
    
    /// Generate keyframes for auto-zoom based on click events.
    ///
    /// When `cursorPath` is provided and non-empty, uses spring-physics zoom
    /// via `ZoomInterpolator` for natural transitions and cursor-following viewport.
    /// Falls back to legacy easeInOut keyframes when cursor data is unavailable.
    ///
    /// - Parameters:
    ///   - clicks: Array of click events
    ///   - clipDuration: Duration of the video clip
    ///   - cursorPath: Optional continuous cursor samples for viewport following
    ///   - config: Configuration for zoom behavior
    /// - Returns: KeyframeAnimation with position and scale keyframes
    static func generateAutoZoomKeyframes(
        from clicks: [ClickSample],
        clipDuration: CMTime,
        cursorPath: [CursorSample]? = nil,
        config: AutoZoomConfig = .default
    ) -> KeyframeAnimation {
        // When cursor data is available, use spring-physics interpolation
        if let cursorPath, !cursorPath.isEmpty {
            let zoomConfig = ZoomInterpolator.Config(
                zoomScale: config.zoomScale,
                minTimeBetweenZooms: config.minTimeBetweenZooms,
                holdDuration: config.holdDuration,
                keyframeRate: 30.0
            )
            let interpolator = ZoomInterpolator(config: zoomConfig)
            return interpolator.generateZoomAnimation(
                clicks: clicks,
                cursorPath: cursorPath,
                clipDuration: clipDuration
            )
        }

        // Legacy path: easeInOut keyframes without cursor following
        var animation = KeyframeAnimation()
        
        guard !clicks.isEmpty else { return animation }
        
        // Sort clicks by timestamp
        let sortedClicks = clicks.sorted { $0.timestamp < $1.timestamp }
        
        var lastZoomEndTime: TimeInterval = 0
        
        for click in sortedClicks {
            // Skip if too close to previous zoom
            if click.timestamp < lastZoomEndTime + config.minTimeBetweenZooms {
                continue
            }
            
            // Convert click timestamp to CMTime
            let clickTime = CMTime(seconds: click.timestamp, preferredTimescale: 600)
            
            // Ensure click is within clip duration
            guard clickTime < clipDuration else { continue }
            
            // Calculate zoom in start time (slightly before click for anticipation)
            let zoomInStart = max(0, click.timestamp - 0.1)
            let zoomInStartTime = CMTime(seconds: zoomInStart, preferredTimescale: 600)
            
            // Zoom in end time
            let zoomInEnd = click.timestamp + config.zoomDuration
            let zoomInEndTime = CMTime(seconds: zoomInEnd, preferredTimescale: 600)
            
            // Hold end time
            let holdEnd = zoomInEnd + config.holdDuration
            let holdEndTime = CMTime(seconds: holdEnd, preferredTimescale: 600)
            
            // Zoom out end time
            let zoomOutEnd = holdEnd + config.zoomOutDuration
            let zoomOutEndTime = CMTime(seconds: zoomOutEnd, preferredTimescale: 600)
            
            // Ensure we don't exceed clip duration
            guard zoomOutEndTime <= clipDuration else { continue }
            
            // Calculate position offset to center on click
            // Click coordinates are normalized (0-1), we need to convert to offset
            // Center of screen is (0.5, 0.5), click is at (click.x, click.y)
            // Offset = (click.x - 0.5) * scale, (click.y - 0.5) * scale
            let centerX = 0.5
            let centerY = 0.5
            
            // Position offset to center click location
            // Note: In video coordinates, (0,0) is center, positive X is right, positive Y is up
            let offsetX = (click.x - centerX) * config.zoomScale
            let offsetY = (click.y - centerY) * config.zoomScale
            
            // Choose easing
            let easing: EasingType = config.easeInOut ? .easeInOut : .linear
            
            // 1. Zoom In: Scale from 1.0 to zoomScale, position to click location
            animation.setKeyframe(property: .scale, at: zoomInStartTime, value: 1.0, easing: easing)
            animation.setKeyframe(property: .scale, at: zoomInEndTime, value: config.zoomScale, easing: easing)
            
            // Position: Move to center click
            animation.setKeyframe(property: .positionX, at: zoomInStartTime, value: 0.0, easing: easing)  // Start at center
            animation.setKeyframe(property: .positionX, at: zoomInEndTime, value: offsetX, easing: easing)
            
            animation.setKeyframe(property: .positionY, at: zoomInStartTime, value: 0.0, easing: easing)  // Start at center
            animation.setKeyframe(property: .positionY, at: zoomInEndTime, value: offsetY, easing: easing)
            
            // 2. Hold: Keep zoomed in
            animation.setKeyframe(property: .scale, at: holdEndTime, value: config.zoomScale, easing: easing)
            animation.setKeyframe(property: .positionX, at: holdEndTime, value: offsetX, easing: easing)
            animation.setKeyframe(property: .positionY, at: holdEndTime, value: offsetY, easing: easing)
            
            // 3. Zoom Out: Return to normal
            animation.setKeyframe(property: .scale, at: zoomOutEndTime, value: 1.0, easing: easing)
            animation.setKeyframe(property: .positionX, at: zoomOutEndTime, value: 0.0, easing: easing)
            animation.setKeyframe(property: .positionY, at: zoomOutEndTime, value: 0.0, easing: easing)
            
            // Update last zoom end time
            lastZoomEndTime = zoomOutEnd
        }
        
        return animation
    }
}

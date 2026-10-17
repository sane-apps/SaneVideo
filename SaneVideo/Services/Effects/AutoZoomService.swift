import AVFoundation
import CoreMedia
import Foundation

/// Service to generate auto-zoom keyframes from click events
@MainActor
class AutoZoomService {
    
    struct AutoZoomConfig {
        var zoomScale: Double = 1.5  // How much to zoom (1.5x = 50% zoom)
        var zoomDuration: TimeInterval = 0.5  // How long to zoom in (seconds)
        var holdDuration: TimeInterval = 1.0  // How long to hold zoom (seconds)
        var zoomOutDuration: TimeInterval = 0.5  // How long to zoom out (seconds)
        var minTimeBetweenZooms: TimeInterval = 0.3  // Minimum time between zooms (prevent rapid-fire)
        var easeInOut: Bool = true
        
        static let `default` = AutoZoomConfig()
    }
    
    /// Generate keyframes for auto-zoom based on click events.
    ///
    /// When `cursorPath` is provided and non-empty, uses spring-physics zoom
    /// via `ZoomInterpolator` for natural transitions and cursor-following viewport.
    /// Falls back to legacy easeInOut keyframes when cursor data is unavailable.
    ///
    /// - Parameters:
    ///   - cursorPath: Optional continuous cursor samples for viewport following
    static func generateAutoZoomKeyframes(
        from clicks: [ClickSample],
        clipDuration: CMTime,
        cursorPath: [CursorSample]? = nil,
        config: AutoZoomConfig = .default
    ) -> KeyframeAnimation {
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

        var animation = KeyframeAnimation()
        
        guard !clicks.isEmpty else { return animation }
        
        let sortedClicks = clicks.sorted { $0.timestamp < $1.timestamp }
        
        var lastZoomEndTime: TimeInterval = 0
        
        for click in sortedClicks {
            if click.timestamp < lastZoomEndTime + config.minTimeBetweenZooms {
                continue
            }
            
            let clickTime = CMTime(seconds: click.timestamp, preferredTimescale: 600)
            
            guard clickTime < clipDuration else { continue }
            
            // Start slightly before the click for anticipation.
            let zoomInStart = max(0, click.timestamp - 0.1)
            let zoomInStartTime = CMTime(seconds: zoomInStart, preferredTimescale: 600)
            
            let zoomInEnd = click.timestamp + config.zoomDuration
            let zoomInEndTime = CMTime(seconds: zoomInEnd, preferredTimescale: 600)
            
            let holdEnd = zoomInEnd + config.holdDuration
            let holdEndTime = CMTime(seconds: holdEnd, preferredTimescale: 600)
            
            let zoomOutEnd = holdEnd + config.zoomOutDuration
            let zoomOutEndTime = CMTime(seconds: zoomOutEnd, preferredTimescale: 600)
            
            guard zoomOutEndTime <= clipDuration else { continue }
            
            // Click coordinates are normalized 0-1 with the center at 0.5; offset = (click - 0.5) * scale.
            let centerX = 0.5
            let centerY = 0.5
            
            // In video coordinates (0,0) is the center, +X is right, +Y is up.
            let offsetX = (click.x - centerX) * config.zoomScale
            let offsetY = (click.y - centerY) * config.zoomScale
            
            let easing: EasingType = config.easeInOut ? .easeInOut : .linear
            
            animation.setKeyframe(property: .scale, at: zoomInStartTime, value: 1.0, easing: easing)
            animation.setKeyframe(property: .scale, at: zoomInEndTime, value: config.zoomScale, easing: easing)
            
            animation.setKeyframe(property: .positionX, at: zoomInStartTime, value: 0.0, easing: easing)  // Start at center
            animation.setKeyframe(property: .positionX, at: zoomInEndTime, value: offsetX, easing: easing)
            
            animation.setKeyframe(property: .positionY, at: zoomInStartTime, value: 0.0, easing: easing)  // Start at center
            animation.setKeyframe(property: .positionY, at: zoomInEndTime, value: offsetY, easing: easing)
            
            animation.setKeyframe(property: .scale, at: holdEndTime, value: config.zoomScale, easing: easing)
            animation.setKeyframe(property: .positionX, at: holdEndTime, value: offsetX, easing: easing)
            animation.setKeyframe(property: .positionY, at: holdEndTime, value: offsetY, easing: easing)
            
            animation.setKeyframe(property: .scale, at: zoomOutEndTime, value: 1.0, easing: easing)
            animation.setKeyframe(property: .positionX, at: zoomOutEndTime, value: 0.0, easing: easing)
            animation.setKeyframe(property: .positionY, at: zoomOutEndTime, value: 0.0, easing: easing)
            
            lastZoomEndTime = zoomOutEnd
        }
        
        return animation
    }
}

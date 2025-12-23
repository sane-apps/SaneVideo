//
//  RenderingService.swift
//  SaneVideo
//
//  Centralized rendering context to ensure stability with System VFX/Reactions.
//

import AVFoundation
import CoreImage
import Metal

/// Provides a shared CIContext to prevent resource collisions and memory corruption 
/// (StackAllocator crashes) during concurrent rendering or source switching.
/// Refactored to be thermal-aware, providing optimized contexts based on system health.
final class RenderingService: @unchecked Sendable {
    /// Global shared instance for application-wide rendering.
    static let shared = RenderingService()

    /// Shared Metal device.
    let mtlDevice: MTLDevice?

    /// Shared Metal command queue for unified rendering.
    let commandQueue: MTLCommandQueue?

    /// The primary Metal-backed context for high-quality rendering.
    private let highQualityContext: CIContext
    
    /// A lightweight context used when the system is under thermal pressure.
    private let throttledContext: CIContext

    /// Returns the appropriate CIContext based on the current thermal state.
    var ciContext: CIContext {
        if ThermalManager.isThrottled {
            return throttledContext
        } else {
            return highQualityContext
        }
    }

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.mtlDevice = device.map { MetalOptimization.configureDevice($0) }
        self.commandQueue = self.mtlDevice?.makeCommandQueue()

        if let device = device {
            // High Quality Context: Tuned for precision
            self.highQualityContext = CIContext(
                mtlDevice: device, 
                options: [
                    .workingColorSpace: NSNull(), 
                    .outputColorSpace: NSNull(),
                    .useSoftwareRenderer: false,
                    .cacheIntermediates: false,
                    .highQualityDownsample: true,
                    .workingFormat: CIFormat.RGBAh, // 16-bit float for VFX
                    CIContextOption.name: "SaneVideoHQContext",
                    CIContextOption.priorityRequestLow: false
                ]
            )
            
            // Throttled Context: Tuned for lower power consumption
            self.throttledContext = CIContext(
                mtlDevice: device,
                options: [
                    .workingColorSpace: NSNull(),
                    .outputColorSpace: NSNull(),
                    .useSoftwareRenderer: false,
                    .cacheIntermediates: false,
                    .highQualityDownsample: false, // Save CPU/GPU on downsampling
                    .workingFormat: CIFormat.RGBA8, // 8-bit for lower memory bandwidth
                    CIContextOption.name: "SaneVideoThrottledContext",
                    CIContextOption.priorityRequestLow: true // Request LOW priority to let system cool down
                ]
            )
        } else {
            let fallback = CIContext(options: [
                .useSoftwareRenderer: false,
                CIContextOption.name: "SaneVideoFallbackContext"
            ])
            self.highQualityContext = fallback
            self.throttledContext = fallback
        }
    }
}

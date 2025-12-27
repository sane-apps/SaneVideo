//
//  MetalOptimization.swift
//  SaneVideo
//
//  Metal/GPU optimization utilities for M1+ Apple Silicon
//

import Metal
import CoreImage
import Foundation

/// Metal optimization utilities for Apple Silicon
enum MetalOptimization {
    
    /// Check if Metal is available and optimized
    static var isMetalAvailable: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }
    
    /// Check if we're running on Apple Silicon (M1+)
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    /// Get optimal pixel format for current hardware
    static func optimalPixelFormat(for quality: RenderQuality) -> CIFormat {
        guard isAppleSilicon else {
            return .RGBA8 // Fallback for Intel
        }
        
        switch quality {
        case .high:
            return .RGBAh // 16-bit float for M1+ high quality
        case .balanced:
            return .RGBAh // Use 16-bit for balanced (M1+ handles it efficiently)
        case .low:
            return .RGBA8 // 8-bit for low power
        }
    }
    
    /// Get optimal command queue priority
    /// Note: MTLCommandQueue doesn't have explicit priority API in current macOS
    /// Priority is managed through CIContext options (priorityRequestLow)
    static func shouldUseLowPriority(for thermalState: ProcessInfo.ThermalState) -> Bool {
        switch thermalState {
        case .nominal, .fair:
            return false
        case .serious, .critical:
            return true
        @unknown default:
            return false
        }
    }
    
    /// Configure Metal device for optimal performance
    static func configureDevice(_ device: MTLDevice) -> MTLDevice {
        // M1+ specific optimizations
        if isAppleSilicon {
            // Enable unified memory benefits
            // Metal automatically uses unified memory on Apple Silicon
            // No explicit configuration needed, but we can verify
            
            // Log device info for debugging
            AppLogger.general.debug("🔧 Metal Device: \(device.name)")
            AppLogger.general.debug("🔧 Unified Memory: \(device.hasUnifiedMemory ? "Yes" : "No")")
            AppLogger.general.debug("🔧 Max Threads Per Threadgroup: \(device.maxThreadsPerThreadgroup.width)")
        }
        
        return device
    }
    
    /// Get recommended batch size for processing
    static func recommendedBatchSize(for operation: OperationType) -> Int {
        guard isAppleSilicon else {
            return 1 // Conservative for Intel
        }
        
        switch operation {
        case .videoFrame:
            return 4 // Process 4 frames at once on M1+
        case .audioBuffer:
            return 8 // Larger batches for audio
        case .visionAnalysis:
            return 2 // Smaller batches for Vision (ANE)
        case .export:
            return 1 // Sequential for export stability
        }
    }
    
    enum RenderQuality {
        case high
        case balanced
        case low
    }
    
    enum OperationType {
        case videoFrame
        case audioBuffer
        case visionAnalysis
        case export
    }
}

/// Extension to RenderingService for Metal optimization
extension RenderingService {
    
    /// Optimize Metal device for current system state
    func optimizeForCurrentState() {
        guard mtlDevice != nil else { return }
        
        // Log optimization state (CIContext switches automatically via ciContext property)
        if ThermalManager.isThrottled {
            AppLogger.general.info("🔧 Metal: Optimizing for thermal throttling")
        } else {
            AppLogger.general.debug("🔧 Metal: Running at full performance")
        }
    }
    
    /// Get optimal CIContext options for current hardware
    func optimalContextOptions() -> [CIContextOption: Any] {
        guard mtlDevice != nil else {
            return [.useSoftwareRenderer: false]
        }
        
        let quality: MetalOptimization.RenderQuality = ThermalManager.isThrottled ? .low : .high
        let format = MetalOptimization.optimalPixelFormat(for: quality)
        
        return [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
            .highQualityDownsample: !ThermalManager.isThrottled,
            .workingFormat: format,
            CIContextOption.name: "SaneVideoOptimizedContext",
            CIContextOption.priorityRequestLow: ThermalManager.isThrottled
        ]
    }
}

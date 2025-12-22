//
//  VoiceIsolationService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

@preconcurrency import AVFoundation
import Combine
import OSLog

/// A service that provides high-quality voice isolation using the native Apple AUSoundIsolation Audio Unit.
/// Available on macOS 13.0+
@MainActor
final class VoiceIsolationService: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.sanevideo.app", category: "VoiceIsolation")
    
    /// The Audio Unit for sound isolation
    private var isolationUnit: AVAudioUnit?
    
    /// Whether voice isolation is currently active and initialized
    private(set) var isReady = false
    
    // MARK: - Initialization
    
    init() {
        Task {
            await prepareIsolationUnit()
        }
    }
    
    // MARK: - Public Interface
    
    /// Prepares the isolation unit asynchronously
    func prepareIsolationUnit() async {
        guard isolationUnit == nil else { return }
        
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_AUSoundIsolation,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        do {
            isolationUnit = try await withCheckedThrowingContinuation { continuation in
                AVAudioUnit.instantiate(with: desc, options: []) { unit, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let unit = unit {
                        continuation.resume(returning: unit)
                    } else {
                        continuation.resume(throwing: NSError(domain: "VoiceIsolationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to instantiate AUSoundIsolation"]))
                    }
                }
            }
            isReady = true
            logger.info("AUSoundIsolation unit instantiated successfully")
        } catch {
            logger.error("Failed to prepare voice isolation unit: \(error.localizedDescription)")
            isReady = false
        }
    }
    
    /// Returns the isolation unit to be added to an AVAudioEngine graph
    func getAudioUnit() -> AVAudioUnit? {
        return isolationUnit
    }
    
    /// Sets the isolation intensity (0.0 to 1.0)
    /// Note: Not all Audio Units support this, but AUSoundIsolation often has a wet/dry or similar parameter
    func setIntensity(_ intensity: Float) {
        guard let unit = isolationUnit else { return }
        // AUSoundIsolation typically has a "Voice Isolation" parameter at index 0
        // We set it to the requested intensity
        AudioUnitSetParameter(unit.audioUnit, 0, kAudioUnitScope_Global, 0, intensity, 0)
    }
}

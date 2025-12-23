//
//  VoiceIsolationService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

@preconcurrency import AVFoundation
import Combine
import OSLog

/// Error types for voice isolation
enum VoiceIsolationError: Error, LocalizedError {
    case instantiationFailed
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .instantiationFailed:
            return "Failed to instantiate AUSoundIsolation audio unit"
        case .timeout:
            return "Voice isolation initialization timed out (AUSoundIsolation unavailable on this system)"
        }
    }
}

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
    
    /// Timeout for AUSoundIsolation instantiation (in seconds)
    private let instantiationTimeoutSeconds: UInt64 = 5
    
    // MARK: - Initialization
    
    init() {
        Task {
            await prepareIsolationUnit()
        }
    }
    
    // MARK: - Public Interface
    
    /// Prepares the isolation unit asynchronously with timeout protection
    func prepareIsolationUnit() async {
        guard isolationUnit == nil else { return }
        
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_AUSoundIsolation,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        logger.info("Attempting to instantiate AUSoundIsolation (timeout: \(self.instantiationTimeoutSeconds)s)...")
        
        do {
            // Use timeout protection: AUSoundIsolation can hang on macOS 26
            isolationUnit = try await withThrowingTaskGroup(of: AVAudioUnit.self) { group in
                // Task 1: Attempt instantiation
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        AVAudioUnit.instantiate(with: desc, options: []) { unit, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else if let unit = unit {
                                continuation.resume(returning: unit)
                            } else {
                                continuation.resume(throwing: VoiceIsolationError.instantiationFailed)
                            }
                        }
                    }
                }
                
                // Task 2: Timeout
                group.addTask {
                    try await Task.sleep(nanoseconds: self.instantiationTimeoutSeconds * 1_000_000_000)
                    throw VoiceIsolationError.timeout
                }
                
                // Return the first successful result, cancel the other
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            isReady = true
            logger.info("AUSoundIsolation unit instantiated successfully")
        } catch VoiceIsolationError.timeout {
            logger.warning("Voice isolation timed out - AUSoundIsolation unavailable on this system")
            isReady = false
        } catch {
            logger.warning("Voice isolation unavailable: \(error.localizedDescription)")
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

@preconcurrency import AVFoundation
import Combine
import OSLog

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
    
    private let logger = Logger(subsystem: "com.sanevideo.SaneVideo", category: "VoiceIsolation")
    
    private var isolationUnit: AVAudioUnit?
    
    private(set) var isReady = false
    
    private var instantiationTimeoutSeconds: UInt64 {
        UInt64(AppConstants.MagicFeatures.voiceIsolationTimeout)
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await prepareIsolationUnit()
        }
    }
    
    // MARK: - Public Interface
    
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
                
                group.addTask {
                    try await Task.sleep(nanoseconds: self.instantiationTimeoutSeconds * 1_000_000_000)
                    throw VoiceIsolationError.timeout
                }
                
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
    
    func getAudioUnit() -> AVAudioUnit? {
        return isolationUnit
    }
    
    /// Sets the isolation intensity (0.0 to 1.0)
    func setIntensity(_ intensity: Float) {
        guard let unit = isolationUnit else { return }
        // AUSoundIsolation typically has a "Voice Isolation" parameter at index 0
        AudioUnitSetParameter(unit.audioUnit, 0, kAudioUnitScope_Global, 0, intensity, 0)
    }
}

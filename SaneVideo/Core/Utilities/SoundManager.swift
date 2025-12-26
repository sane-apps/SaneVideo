import AudioToolbox
import Foundation
import AppKit

/// Centralized manager for auditory feedback (UX Delight)
@MainActor
final class SoundManager {

    init() {}

    // System Sound IDs can be found via AudioToolbox research or testing.
    // 1113 = Begin Recording (standard on macOS)
    // 1114 = End Recording
    // 1117 = Modern Beep for Error/Warning

    private let startSoundID: SystemSoundID = 1113
    private let stopSoundID: SystemSoundID = 1114
    private let errorSoundID: SystemSoundID = 1053

    nonisolated func playStartRecording() {
        AudioServicesPlaySystemSound(startSoundID)
    }

    nonisolated func playStopRecording() {
        AudioServicesPlaySystemSound(stopSoundID)
    }

    nonisolated func playError() {
        // Play system alert sound
        AudioServicesPlaySystemSound(errorSoundID)
    }

    nonisolated func playSuccess() {
        // Use NSSound for higher volume control and distinctive "done" chime
        if let sound = NSSound(named: "Glass") {
            sound.volume = 1.0
            sound.play()
        }
    }
}

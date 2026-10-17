import Foundation

struct MagicFixOptions: Codable, Equatable {
    var removeSilence = true
    var removeFillers = true
    var generateCaptions = true
    var enhanceAudio = true
    var applyHighlightCursor = true
    var smoothJumpCuts = true

    /// dB below which audio counts as silence (-60 keeps more, -30 cuts more).
    var silenceThreshold = -45.0
    var minSilenceDuration = 0.3
    /// Seconds kept on each side of a cut.
    var silenceMargin = 0.1
    /// Share of loud samples a region may contain and still count as silent.
    var silenceTolerance = 0.1

    static let proClean = MagicFixOptions()

    static let minimal = MagicFixOptions(
        removeSilence: true,
        removeFillers: false,
        generateCaptions: false,
        enhanceAudio: false,
        applyHighlightCursor: false,
        smoothJumpCuts: false
    )

    var presetName: String {
        if self == .minimal {
            return "Minimal Fix"
        }
        if self == .proClean {
            return "Pro Clean-up"
        }
        return "Custom"
    }

    var presetDescription: String {
        if self == .minimal {
            return "Just remove silence."
        }
        if self == .proClean {
            return "Silence, filler words, captions, clearer speech and smoother cuts."
        }
        return "Custom settings"
    }

    var isEmpty: Bool {
        !removeSilence && !removeFillers && !generateCaptions && !enhanceAudio && !smoothJumpCuts
    }

    var summary: String {
        let parts = [
            removeSilence ? "Silence" : nil,
            removeFillers ? "Fillers" : nil,
            generateCaptions ? "Captions" : nil,
            enhanceAudio ? "Speech" : nil,
            smoothJumpCuts ? "Cuts" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "No options selected" : parts.joined(separator: ", ")
    }
}

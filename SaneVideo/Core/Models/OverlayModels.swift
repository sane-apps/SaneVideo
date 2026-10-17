import CoreGraphics
import Foundation

enum PresenterOverlayCorner: String, Codable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Starting size and corner for the camera bubble over a screen recording.
struct PresenterOverlayLayout: Codable, Equatable, Hashable, Sendable {
    var width: CGFloat
    var height: CGFloat
    var corner: PresenterOverlayCorner
    var margin: CGFloat = 40

    static let standard = PresenterOverlayLayout(width: 320, height: 214, corner: .bottomRight)
}

/// The project's teleprompter script and how it scrolls.
struct SpeakerNotes: Codable, Equatable, Hashable, Sendable {
    var text = ""
    var fontSize = 30.0
    var opacity = 0.9
    var widthFraction = 0.72
    var scrollSpeed = 28.0
    var isMirrored = false
    var isVisible = false

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Click and keystroke overlays drawn on screen recordings.
struct InteractionOverlayStyle: Codable, Equatable, Hashable, Sendable {
    var highlightClicks = true
    var spotlightCursor = true
    var showKeystrokes = true
    var clickRingScale = 1.0
    var spotlightOpacity = 0.25
}

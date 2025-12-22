import SwiftUI

/// Defines the visual style for captions
struct CaptionStyle: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String

    // Text Appearance
    var fontName: String
    var fontSize: CGFloat
    var textColor: String // Hex
    var isBold: Bool
    var isItalic: Bool

    // Background / Stroke
    var backgroundColor: String? // Hex, nil = none
    var strokeColor: String? // Hex
    var strokeWidth: CGFloat
    var shadowRadius: CGFloat
    var shadowColor: String?

    // Active Word Highlight (Karaoke)
    var activeTextColor: String? // Hex, defaults to yellow/accent if nil
    var highlightStyle: HighlightStyle = .none

    public enum HighlightStyle: String, Codable, Equatable, Hashable, Sendable {
        case none
        case pop // Scale up active word
        case glow // Glow effect
        case underline
        case background // Highlight background like marker
    }

    init(
        id: UUID = UUID(),
        name: String,
        fontName: String = "SF Pro Rounded",
        fontSize: CGFloat = 48,
        textColor: String = "#FFFFFF",
        isBold: Bool = true,
        isItalic: Bool = false,
        backgroundColor: String? = nil,
        strokeColor: String? = nil,
        strokeWidth: CGFloat = 0,
        shadowRadius: CGFloat = 2,
        shadowColor: String? = "#000000",
        activeTextColor: String? = nil,
        highlightStyle: HighlightStyle = .none
    ) {
        self.id = id
        self.name = name
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.isBold = isBold
        self.isItalic = isItalic
        self.backgroundColor = backgroundColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.shadowRadius = shadowRadius
        self.shadowColor = shadowColor
        self.activeTextColor = activeTextColor
        self.highlightStyle = highlightStyle
    }

    // MARK: - Factory Methods

    func withFont(_ newFontName: String) -> CaptionStyle {
        var copy = self
        copy.fontName = newFontName
        return copy
    }

    // MARK: - Classic Presets

    static let classic = CaptionStyle(
        name: "Classic",
        fontName: "SF Pro Rounded",
        fontSize: 48,
        textColor: "#FFFFFF",
        strokeColor: "#000000",
        strokeWidth: 2,
        shadowRadius: 4
    )

    static let bold = CaptionStyle(
        name: "Bold",
        fontName: "SF Pro Display",
        fontSize: 60,
        textColor: "#FFFFFF",
        isBold: true,
        strokeColor: "#000000",
        strokeWidth: 3,
        shadowRadius: 5
    )

    static let minimal = CaptionStyle(
        name: "Minimal",
        fontName: "SF Pro Text",
        fontSize: 40,
        textColor: "#FFFFFF",
        shadowRadius: 2,
        shadowColor: "#00000080"
    )

    static let modern = CaptionStyle(
        name: "Modern",
        fontName: "Avenir Next",
        fontSize: 52,
        textColor: "#FFFFFF",
        isBold: true,
        backgroundColor: "#000000CC",
        shadowRadius: 0
    )

    static let cinematic = CaptionStyle(
        name: "Cinematic",
        fontName: "Georgia",
        fontSize: 44,
        textColor: "#FFFFFF",
        strokeColor: "#000000",
        strokeWidth: 1.5,
        shadowRadius: 0
    )

    // MARK: - Social Media Styles

    static let tikTok = CaptionStyle(
        name: "TikTok",
        fontName: "Futura",
        fontSize: 56,
        textColor: "#FFFFFF",
        isBold: true,
        strokeColor: "#000000",
        strokeWidth: 4,
        shadowRadius: 0
    )

    static let instagram = CaptionStyle(
        name: "Instagram",
        fontName: "Helvetica Neue",
        fontSize: 44,
        textColor: "#FFFFFF",
        isBold: true,
        backgroundColor: "#00000066",
        shadowRadius: 8,
        shadowColor: "#000000"
    )

    static let reels = CaptionStyle(
        name: "Reels",
        fontName: "SF Pro Rounded",
        fontSize: 52,
        textColor: "#FF0050",
        isBold: true,
        strokeColor: "#FFFFFF",
        strokeWidth: 3,
        shadowRadius: 6
    )

    static let snapchat = CaptionStyle(
        name: "Snapchat",
        fontName: "Helvetica Neue",
        fontSize: 48,
        textColor: "#FFFC00",
        isBold: true,
        backgroundColor: "#00000099",
        shadowRadius: 0
    )

    static let youtube = CaptionStyle(
        name: "YouTube",
        fontName: "Roboto",
        fontSize: 42,
        textColor: "#FFFFFF",
        backgroundColor: "#000000CC",
        shadowRadius: 0
    )

    static let viral = CaptionStyle(
        name: "Viral",
        fontName: "Impact",
        fontSize: 56,
        textColor: "#FFFFFF",
        isBold: true,
        strokeColor: "#000000",
        strokeWidth: 4,
        shadowRadius: 0
    )

    // MARK: - Effect Styles

    static let neon = CaptionStyle(
        name: "Neon",
        fontName: "Futura",
        fontSize: 52,
        textColor: "#00FFFF",
        isBold: true,
        strokeColor: "#FF00FF",
        strokeWidth: 2,
        shadowRadius: 20,
        shadowColor: "#00FFFF"
    )

    static let neonPink = CaptionStyle(
        name: "Neon Pink",
        fontName: "Futura",
        fontSize: 52,
        textColor: "#FF1493",
        isBold: true,
        strokeColor: "#FF69B4",
        strokeWidth: 2,
        shadowRadius: 20,
        shadowColor: "#FF1493"
    )

    static let glitch = CaptionStyle(
        name: "Glitch",
        fontName: "Courier New",
        fontSize: 48,
        textColor: "#00FFFF",
        isBold: true,
        strokeColor: "#FF0000",
        strokeWidth: 2,
        shadowRadius: 4,
        shadowColor: "#FF0000"
    )

    static let pop = CaptionStyle(
        name: "Pop",
        fontName: "Futura",
        fontSize: 56,
        textColor: "#FFEE00",
        isBold: true,
        strokeColor: "#000000",
        strokeWidth: 4,
        shadowRadius: 0
    )

    static let karaoke = CaptionStyle(
        name: "Karaoke",
        fontName: "SF Pro Display",
        fontSize: 52,
        textColor: "#FFFFFF",
        isBold: true,
        backgroundColor: "#000000CC",
        strokeColor: "#FFFFFF",
        strokeWidth: 1,
        shadowRadius: 0,
        activeTextColor: "#FFD700", // Gold
        highlightStyle: .pop
    )

    // MARK: - Professional Styles

    static let broadcast = CaptionStyle(
        name: "Broadcast",
        fontName: "Helvetica Neue",
        fontSize: 38,
        textColor: "#FFFFFF",
        backgroundColor: "#1A1A1ACC",
        shadowRadius: 0
    )

    static let documentary = CaptionStyle(
        name: "Documentary",
        fontName: "Georgia",
        fontSize: 36,
        textColor: "#F5F5F5",
        isItalic: true,
        backgroundColor: "#00000099",
        shadowRadius: 2
    )

    static let gaming = CaptionStyle(
        name: "Gaming",
        fontName: "Impact",
        fontSize: 54,
        textColor: "#00FF00",
        isBold: true,
        strokeColor: "#000000",
        strokeWidth: 3,
        shadowRadius: 8,
        shadowColor: "#00FF00"
    )

    static let podcast = CaptionStyle(
        name: "Podcast",
        fontName: "SF Pro Text",
        fontSize: 40,
        textColor: "#FFFFFF",
        backgroundColor: "#333333E6",
        shadowRadius: 0
    )

    static let presentation = CaptionStyle(
        name: "Presentation",
        fontName: "Helvetica Neue",
        fontSize: 42,
        textColor: "#FFFFFF",
        backgroundColor: "#0066CCCC",
        shadowRadius: 0
    )

    // MARK: - Aesthetic Styles

    static let retro = CaptionStyle(
        name: "Retro VHS",
        fontName: "Courier New",
        fontSize: 44,
        textColor: "#FFFFFF",
        strokeColor: "#FF0000",
        strokeWidth: 1,
        shadowRadius: 6,
        shadowColor: "#00FFFF"
    )

    static let handwritten = CaptionStyle(
        name: "Handwritten",
        fontName: "Marker Felt",
        fontSize: 48,
        textColor: "#FFFFFF",
        shadowRadius: 4,
        shadowColor: "#00000080"
    )

    static let comic = CaptionStyle(
        name: "Comic",
        fontName: "Comic Sans MS",
        fontSize: 50,
        textColor: "#FFFFFF",
        isBold: true,
        strokeColor: "#000000",
        strokeWidth: 3,
        shadowRadius: 0
    )

    static let typewriter = CaptionStyle(
        name: "Typewriter",
        fontName: "American Typewriter",
        fontSize: 40,
        textColor: "#F5F5DC",
        shadowRadius: 2,
        shadowColor: "#00000080"
    )

    static let elegant = CaptionStyle(
        name: "Elegant",
        fontName: "Didot",
        fontSize: 46,
        textColor: "#FFFFFF",
        isItalic: true,
        shadowRadius: 4,
        shadowColor: "#00000080"
    )

    static let chalk = CaptionStyle(
        name: "Chalk",
        fontName: "Chalkduster",
        fontSize: 44,
        textColor: "#FFFFFF",
        shadowRadius: 3,
        shadowColor: "#000000"
    )

    // MARK: - All Presets (Organized by Category)

    static let socialPresets: [CaptionStyle] = [.tikTok, .instagram, .reels, .snapchat, .youtube, .viral]
    static let effectPresets: [CaptionStyle] = [.neon, .neonPink, .glitch, .pop, .karaoke]
    static let proPresets: [CaptionStyle] = [.broadcast, .documentary, .gaming, .podcast, .presentation]
    static let aestheticPresets: [CaptionStyle] = [.retro, .handwritten, .comic, .typewriter, .elegant, .chalk]
    static let classicPresets: [CaptionStyle] = [.classic, .bold, .minimal, .modern, .cinematic]

    static let allPresets: [CaptionStyle] = classicPresets + socialPresets + effectPresets + proPresets + aestheticPresets
}

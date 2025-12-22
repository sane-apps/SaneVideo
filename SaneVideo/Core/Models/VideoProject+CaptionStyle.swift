import Foundation

extension VideoProject {
    /// Current caption style (computed from stored name)
    /// Moving this to extension to avoid MainActor inference on the main Codable struct
    var captionStyle: CaptionStyle {
        get {
            let baseStyle = CaptionStyle.allPresets.first { $0.name == captionStyleName } ?? .classic
            if let fontName = captionFontName {
                return baseStyle.withFont(fontName)
            }
            return baseStyle
        }
        set {
            captionStyleName = newValue.name
            // Reset font override when changing style preset
            captionFontName = nil
        }
    }
}

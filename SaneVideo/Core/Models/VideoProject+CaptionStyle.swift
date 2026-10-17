import Foundation

extension VideoProject {
    /// Current caption style (computed from stored name)
    /// Lives in an extension so the Codable struct does not infer MainActor.
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
            captionFontName = nil
        }
    }
}

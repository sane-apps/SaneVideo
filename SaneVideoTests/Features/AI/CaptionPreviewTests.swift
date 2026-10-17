// Every caption preset must be drawable: a font, a positive size and a text color.

@testable import SaneVideo
import Testing

@Suite("Caption preset rendering inputs")
struct CaptionPreviewTests {
    @Test(
        "Caption preset has a font, positive size and text color",
        arguments: [CaptionStyle.classic, .bold, .tikTok, .instagram, .youtube]
    )
    func presetIsDrawable(_ style: CaptionStyle) {
        #expect(!style.fontName.isEmpty)
        #expect(style.fontSize > 0)
        #expect(!style.textColor.isEmpty)
    }
}

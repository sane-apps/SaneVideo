import AVFoundation
import SwiftUI

struct CaptionOverlayView: View {
    let caption: Caption?
    let currentTime: CMTime
    var style: CaptionStyle = .classic
    /// Normalized offset from the default caption band, same units the export uses.
    var offset: CGSize = .zero

    // Same band as TextLayerBuilder: x 0.1, y 0.8, 80% wide, 15% tall.
    private static let band = CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.15)
    /// Height of the 1920x1080 frame the editor's playback composition renders.
    private static let referenceHeight: CGFloat = 1080

    var body: some View {
        if let caption = caption {
            GeometryReader { geo in
                let band = Self.band.offsetBy(dx: offset.width, dy: offset.height)
                KaraokeTextRenderer(
                    caption: caption,
                    currentTime: currentTime,
                    style: style,
                    // Export sizes text in pixels of the video frame; scale to this preview so it matches.
                    scale: geo.size.height / Self.referenceHeight
                )
                .padding(8)
                .background {
                    if let bgColor = style.backgroundColor, style.highlightStyle != .background {
                        RoundedRectangle(cornerRadius: Theme.Dimensions.smallCornerRadius)
                            .fill(Color(hex: bgColor))
                    }
                }
                .frame(width: band.width * geo.size.width)
                .position(x: band.midX * geo.size.width, y: band.midY * geo.size.height)
            }
            // Dragging is handled by CanvasOverlay underneath.
            .allowsHitTesting(false)
            // Stable ID so the caption doesn't jump; it changes only when the caption changes, not on text edits.
            .id("\(caption.id)-\(caption.startTime.seconds)")
            .transition(.opacity)
        }
    }
}

// MARK: - Karaoke Renderer

struct KaraokeTextRenderer: View {
    let caption: Caption
    let currentTime: CMTime
    let style: CaptionStyle
    var scale: CGFloat = 1

    private var fontSize: CGFloat { style.fontSize * scale }

    var body: some View {
        // After a text edit the timed words are stale, so show the edited text instead.
        if let words = caption.words, caption.textMatchesWords {
            FlowLayout(alignment: .center, spacing: 6 * scale) {
                ForEach(words) { word in
                    let isWordActive = isWordActive(word)

                    Text(word.text)
                        .font(.custom(style.fontName, size: fontSize))
                        .fontWeight(style.isBold ? .bold : .regular)
                        .italic(style.isItalic)
                        .foregroundColor(textColor(for: isWordActive))
                        .shadow(color: Color(hex: style.shadowColor ?? "#000000").opacity(style.shadowRadius > 0 ? 0.8 : 0), radius: style.shadowRadius * scale, x: 0, y: 2 * scale)
                        .scaleEffect(isWordActive && style.highlightStyle == .pop ? 1.2 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isWordActive)
                        .background(
                            style.highlightStyle == .background && isWordActive ?
                            Color(hex: style.activeTextColor ?? style.textColor).opacity(0.3).cornerRadius(4) : nil
                        )
                }
            }
        } else {
            // Plain text wraps inside the band, like the export. displayText strips Whisper tokens.
            Text(caption.displayText)
                .font(.custom(style.fontName, size: fontSize))
                .fontWeight(style.isBold ? .bold : .regular)
                .italic(style.isItalic)
                .foregroundColor(Color(hex: style.textColor))
                .multilineTextAlignment(.center)
                .shadow(color: Color(hex: style.shadowColor ?? "#000000").opacity(0.8), radius: style.shadowRadius * scale, x: 0, y: 2 * scale)
        }
    }

    private func isWordActive(_ word: CaptionWord) -> Bool {
        let wordStart = CMTime(seconds: word.start, preferredTimescale: 600)
        let wordEnd = CMTime(seconds: word.end, preferredTimescale: 600)
        return currentTime >= wordStart && currentTime <= wordEnd
    }

    private func textColor(for isActive: Bool) -> Color {
        if isActive, let activeHex = style.activeTextColor {
            return Color(hex: activeHex)
        }
        return Color(hex: style.textColor)
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var alignment: Alignment = .center
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // With no width proposed, lay out on one line instead of collapsing to zero width.
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))

            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            widest = max(widest, x - spacing)
        }

        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        // Rows are buffered so center and trailing alignment can be applied.

        var currentRow: [LayoutSubviews.Element] = []
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))

            if currentRowWidth + size.width + (currentRow.isEmpty ? 0 : spacing) > width {
                placeRow(currentRow, width: currentRowWidth, y: y, bounds: bounds)
                y += rowHeight + spacing
                currentRow = []
                currentRowWidth = 0
                rowHeight = 0
            }

            currentRow.append(subview)
            currentRowWidth += size.width + (currentRow.count > 1 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }

        if !currentRow.isEmpty {
            placeRow(currentRow, width: currentRowWidth, y: y, bounds: bounds)
        }
    }

    private func placeRow(_ subviews: [LayoutSubviews.Element], width rowWidth: CGFloat, y: CGFloat, bounds: CGRect) {
        var x: CGFloat = bounds.minX

        if alignment.horizontal == .center {
            x += (bounds.width - rowWidth) / 2
        } else if alignment.horizontal == .trailing {
            x += bounds.width - rowWidth
        }

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            // Assumes one font size, so subviews are not centered vertically in the row.
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}

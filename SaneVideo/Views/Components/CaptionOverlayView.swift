import AVFoundation
import SwiftUI

struct CaptionOverlayView: View {
    let caption: Caption?
    let currentTime: CMTime
    var style: CaptionStyle = .classic
    @Binding var offset: CGSize

    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0

    var body: some View {
        if let caption = caption {
            ZStack {
                if let bgColor = style.backgroundColor, style.highlightStyle != .background {
                    RoundedRectangle(cornerRadius: Theme.Dimensions.smallCornerRadius)
                        .fill(Color(hex: bgColor))
                        .opacity(style.backgroundColor != nil ? 1 : 0)
                }

                KaraokeTextRenderer(
                    caption: caption,
                    currentTime: currentTime,
                    style: style
                )
                .padding(8)
            }
            .padding(style.backgroundColor != nil ? 8 : 0)
            .padding(.bottom, 40)
            .scaleEffect(scale)
            .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in dragOffset = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in scale = max(0.5, min(3.0, value)) }
            )
            .onHover { inside in
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            // Stable ID so the caption doesn't jump; it changes only when the caption changes, not on text edits.
            .id("\(caption.id)-\(caption.startTime.seconds)")
            .transition(.scale.combined(with: .opacity))
            // Animate only when the caption changes, not on text edits, to prevent jumping.
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: caption.id)
        }
    }
}

// MARK: - Karaoke Renderer

struct KaraokeTextRenderer: View {
    let caption: Caption
    let currentTime: CMTime
    let style: CaptionStyle

    var body: some View {
        FlowLayout(alignment: .center, spacing: 6) {
            if let words = caption.words, !words.isEmpty {
                ForEach(words) { word in
                    let isWordActive = isWordActive(word)

                    Text(word.text)
                        .font(.custom(style.fontName, size: style.fontSize))
                        .fontWeight(style.isBold ? .bold : .regular)
                        .italic(style.isItalic)
                        .foregroundColor(textColor(for: isWordActive))
                        .shadow(color: Color(hex: style.shadowColor ?? "#000000").opacity(style.shadowRadius > 0 ? 0.8 : 0), radius: style.shadowRadius, x: 0, y: 2)
                        .scaleEffect(isWordActive && style.highlightStyle == .pop ? 1.2 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isWordActive)
                        .background(
                            style.highlightStyle == .background && isWordActive ?
                            Color(hex: style.activeTextColor ?? style.textColor).opacity(0.3).cornerRadius(4) : nil
                        )
                }
            } else {
                // Use displayText to strip Whisper tokens like <|startoftranscript|>
                Text(caption.displayText)
                    .font(.custom(style.fontName, size: style.fontSize))
                    .fontWeight(style.isBold ? .bold : .regular)
                    .italic(style.isItalic)
                    .foregroundColor(Color(hex: style.textColor))
                    .shadow(color: Color(hex: style.shadowColor ?? "#000000").opacity(0.8), radius: style.shadowRadius, x: 0, y: 2)
            }
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
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))

            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: width, height: y + rowHeight)
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

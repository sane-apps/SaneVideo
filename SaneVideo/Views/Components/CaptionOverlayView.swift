//
//  CaptionOverlayView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

struct CaptionOverlayView: View {
    let caption: Caption? // Full Caption object
    let currentTime: CMTime
    var style: CaptionStyle = .classic
    @Binding var offset: CGSize

    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0

    var body: some View {
        if let caption = caption {
            ZStack {
                // Background Styling (container-level)
                if let bgColor = style.backgroundColor, style.highlightStyle != .background {
                    RoundedRectangle(cornerRadius: Theme.Dimensions.smallCornerRadius)
                        .fill(Color(hex: bgColor))
                        .opacity(style.backgroundColor != nil ? 1 : 0)
                }

                // Text Renderer (Karaoke or Classic)
                KaraokeTextRenderer(
                    caption: caption,
                    currentTime: currentTime,
                    style: style
                )
                .padding(8) // Padding inside container
            }
            .padding(style.backgroundColor != nil ? 8 : 0) // Outer padding if background exists
            // Positioning & Interaction (Unchanged)
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
            // CRITICAL FIX: Use stable ID to prevent position jumping
            // Only change ID when caption actually changes, not on every text update
            .id("\(caption.id)-\(caption.startTime.seconds)")
            .transition(.scale.combined(with: .opacity))
            // CRITICAL FIX: Remove animation on text change to prevent jumping
            // Only animate on caption change (handled by transition)
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
        // Use FlowLayout for word wrapping
        // Simple horizontal stack for now, assuming short captions or single line is preferred for style.
        // For multi-line, we'd need a proper FlowLayout. Let's stick to wrapping text if possible,
        // but customizing individual Text views in SwiftUI requires a FlowLayout or putting them in a paragraph.
        //
        // Workaround: Use a ZStack with layout logic OR `Text` concatenation if we don't need distinct per-word geometry (but we do for scale/pop).
        //
        // Correct approach: `Layout` protocol (Grid/Flow)

        FlowLayout(alignment: .center, spacing: 6) {
            // If we have word timestamps, render individually
            if let words = caption.words, !words.isEmpty {
                ForEach(words) { word in
                    let isWordActive = isWordActive(word)

                    Text(word.text)
                        .font(.custom(style.fontName, size: style.fontSize))
                        .fontWeight(style.isBold ? .bold : .regular)
                        .italic(style.isItalic)
                        .foregroundColor(textColor(for: isWordActive))
                        // Stroke / Shadow effects handled here per word?
                        // Applying complex shadows per word can be expensive & messy.
                        // Better to apply standard style, then override color/scale.
                        .shadow(color: Color(hex: style.shadowColor ?? "#000000").opacity(style.shadowRadius > 0 ? 0.8 : 0), radius: style.shadowRadius, x: 0, y: 2)
                        // Active Animation (Pop)
                        .scaleEffect(isWordActive && style.highlightStyle == .pop ? 1.2 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isWordActive)
                        // Background Highlight
                        .background(
                            style.highlightStyle == .background && isWordActive ?
                            Color(hex: style.activeTextColor ?? style.textColor).opacity(0.3).cornerRadius(4) : nil
                        )
                }
            } else {
                // Fallback: Just render the full text if no word data
                // CRITICAL FIX: Use displayText to strip Whisper tokens like <|startoftranscript|>
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
        // Add a tiny buffer for smoothness
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
// Using frame-based layout for word wrapping

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
                // New Line
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

        // This simple impl doesn't strictly honor 'alignment' within lines (just left-aligned wrapping).
        // For true center alignment, we'd need 2 passes.
        // Let's implement row-buffering for center/trailing alignment.

        var currentRow: [LayoutSubviews.Element] = []
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))

            if currentRowWidth + size.width + (currentRow.isEmpty ? 0 : spacing) > width {
                // Place Row
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

        // Final Row
        if !currentRow.isEmpty {
            placeRow(currentRow, width: currentRowWidth, y: y, bounds: bounds)
        }
    }

    private func placeRow(_ subviews: [LayoutSubviews.Element], width rowWidth: CGFloat, y: CGFloat, bounds: CGRect) {
        // Calculate X start based on alignment
        var x: CGFloat = bounds.minX

        if alignment.horizontal == .center {
            x += (bounds.width - rowWidth) / 2
        } else if alignment.horizontal == .trailing {
            x += bounds.width - rowWidth
        }

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            // Center vertically in row
            // We need max row height for this... simplified to assume consistent font size
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}

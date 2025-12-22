//
//  CaptionStylePreview.swift
//  SaneVideo
//
//  Preview thumbnail for caption style selection
//

import SwiftUI

/// Preview thumbnail showing how a caption style looks
struct CaptionStylePreview: View {
    let style: CaptionStyle

    var body: some View {
        VStack(spacing: 6) {
            // Larger preview with sample text
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 50)

                // Sample caption text
                Text("Hello")
                    .font(.custom(style.fontName, size: 12))
                    .fontWeight(style.isBold ? .bold : .regular)
                    .italic(style.isItalic)
                    .foregroundColor(Color(hex: style.textColor))
                    .shadow(
                        color: Color(hex: style.shadowColor ?? "#000000").opacity(style.shadowRadius > 0 ? 0.5 : 0),
                        radius: style.shadowRadius,
                        x: 0,
                        y: 1
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: style.backgroundColor ?? "#00000000"))
                    .cornerRadius(4)
            }

            Text(style.name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

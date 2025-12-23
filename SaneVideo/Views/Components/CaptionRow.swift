//
//  CaptionRow.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

struct CaptionRow: View {
    @Binding var caption: Caption
    let clipStart: CMTime
    let isActive: Bool
    let onSeek: () -> Void
    let onDelete: () -> Void
    let style: CaptionStyle
    
    @FocusState private var isFocused: Bool
    @State private var showPreview = false
    
    init(caption: Binding<Caption>, clipStart: CMTime, isActive: Bool, style: CaptionStyle, onSeek: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self._caption = caption
        self.clipStart = clipStart
        self.isActive = isActive
        self.style = style
        self.onSeek = onSeek
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                // Timecode
                Text(formatTime(caption.startTime))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                    .onTapGesture {
                        onSeek()
                    }
                
                // Editable Text
                TextField(String(localized: "caption.placeholder", defaultValue: "Caption"), text: $caption.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .accessibilityIdentifier("caption.text_field")
                    .onChange(of: isFocused) { _, newValue in
                        showPreview = newValue
                    }
                
                if isFocused {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .accessibilityIdentifier("caption.action.delete")
                }
            }
            
            // Live preview when editing
            if showPreview && !caption.text.isEmpty {
                CaptionPreview(text: caption.text, style: style)
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 12)
        .padding(Theme.Dimensions.padding)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(Theme.Dimensions.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius)
                .stroke(isFocused ? Color.accentColor : (isActive ? Color.accentColor.opacity(0.5) : Color.clear), lineWidth: isFocused ? 2 : (isActive ? 1 : 0))
        )
        .shadow(color: isFocused ? Color.accentColor.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .animation(.smoothUI, value: isFocused)
        .animation(.smoothUI, value: isActive)
        .smoothAppear()
        .onTapGesture {
            if !isFocused {
                onSeek()
            }
        }
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let totalSeconds = Int(time.seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct CaptionPreview: View {
    let text: String
    let style: CaptionStyle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Render caption with current style (simplified version of CaptionOverlayView)
            Text(text)
                .font(.custom(style.fontName, size: min(style.fontSize, 24))) // Smaller for preview
                .fontWeight(style.isBold ? .bold : .regular)
                .italic(style.isItalic)
                .foregroundColor(Color(hex: style.textColor))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.7)) // Dark background for visibility
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: style.strokeColor ?? "#000000"), lineWidth: CGFloat(style.strokeWidth))
                )
                .shadow(color: Color(hex: style.shadowColor ?? "#000000").opacity(0.8), radius: CGFloat(style.shadowRadius), x: 0, y: 2)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 8)
    }
}

//
//  ThumbnailUIModels.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import AppKit
import SwiftUI

/// Thumbnail style presets
enum ThumbnailStyle: String, CaseIterable, Identifiable {
    case original = "thumbnail.style.original"
    case vibrant = "thumbnail.style.vibrant"
    case dramatic = "thumbnail.style.dramatic"
    case warm = "thumbnail.style.warm"
    case cool = "thumbnail.style.cool"
    case bw = "thumbnail.style.bw"
    
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return String(localized: "thumbnail.style.original", defaultValue: "Original")
        case .vibrant: return String(localized: "thumbnail.style.vibrant", defaultValue: "Vibrant")
        case .dramatic: return String(localized: "thumbnail.style.dramatic", defaultValue: "Dramatic")
        case .warm: return String(localized: "thumbnail.style.warm", defaultValue: "Warm")
        case .cool: return String(localized: "thumbnail.style.cool", defaultValue: "Cool")
        case .bw: return String(localized: "thumbnail.style.bw", defaultValue: "B&W")
        }
    }

    var description: String {
        switch self {
        case .original: return "Keeps the frame untouched for accurate product shots."
        case .vibrant: return "Boosts color and contrast when the original frame feels flat."
        case .dramatic: return "Adds mood and punch for launch thumbnails or bold announcements."
        case .warm: return "Leans friendly and inviting for tutorials, onboarding, and human-led demos."
        case .cool: return "Crisp blue-led look that fits technical product marketing."
        case .bw: return "High-contrast monochrome when shape and typography matter more than color."
        }
    }
    
    var icon: String {
        switch self {
        case .original: return "photo"
        case .vibrant: return "sparkles"
        case .dramatic: return "moon.fill"
        case .warm: return "sun.max.fill"
        case .cool: return "snowflake"
        case .bw: return "circle.lefthalf.filled"
        }
    }
}

/// Candidate thumbnail frame with metadata
struct ThumbnailCandidate {
    let image: NSImage
    let label: String
    let score: Float
    let time: CMTime
}

/// Card view for displaying a thumbnail candidate
struct ThumbnailCard: View {
    let image: NSImage
    let label: String
    let score: Float
    let isSelected: Bool
    let id: String
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(width: 100, height: 56)
                    .clipped()
                    .cornerRadius(6)
                
                HStack(spacing: 2) {
                    Text(label)
                        .font(Theme.Typography.meta)
                    if score > 0 {
                        Image(systemName: "face.smiling.fill")
                            .font(.system(size: Theme.Typography.fontSizeSM, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .help(score > 0 ? "\(label) • AI-ranked as a promising frame." : label)
    }
}

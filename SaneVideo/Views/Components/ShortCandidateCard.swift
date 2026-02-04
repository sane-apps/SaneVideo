//
//  ShortCandidateCard.swift
//  SaneVideo
//
//  Card view for displaying a short-form video candidate
//

import AVFoundation
import SwiftUI

struct ShortCandidateCard: View {
    let candidate: ShortCandidate
    let isSelected: Bool
    let sourceClip: VideoClip?
    let onTap: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.stone.opacity(0.2))
                        .frame(height: 120)
                        .overlay {
                            Image(systemName: "film")
                                .font(.title)
                                .foregroundStyle(Color.stone)
                        }
                }

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(candidate.durationLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding(6)
                    }
                }

                // Selection overlay
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .cornerRadius(8)

            // Info
            HStack {
                // Score badge
                Text(candidate.scoreLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scoreColor.opacity(0.2))
                    .foregroundStyle(scoreColor)
                    .cornerRadius(4)

                // Time
                Text(formatTime(candidate.startTime))
                    .font(.caption)
                    .foregroundStyle(Color.stone)

                Spacer()
            }

            // Highlights
            if !candidate.highlights.isEmpty {
                HStack(spacing: 4) {
                    ForEach(candidate.highlights, id: \.self) { highlight in
                        Image(systemName: highlight.icon)
                            .font(.caption2)
                            .foregroundStyle(Color.stone)
                    }
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.stone.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityIdentifier("repurposing.candidate.\(candidate.id)")
        .task {
            await loadThumbnail()
        }
    }

    private var scoreColor: Color {
        switch candidate.score {
        case 0.8...: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func loadThumbnail() async {
        guard let clip = sourceClip else { return }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        do {
            let (cgImage, _) = try await generator.image(at: candidate.timeRange.start)
            await MainActor.run {
                self.thumbnail = NSImage(cgImage: cgImage, size: .zero)
            }
        } catch {
            // Keep placeholder
        }
    }
}

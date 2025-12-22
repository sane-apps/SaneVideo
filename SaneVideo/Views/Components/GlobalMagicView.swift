//
//  GlobalMagicView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct GlobalMagicView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerView
                    
                    // PRO BATCH TOOLS
                    VStack(spacing: 16) {
                        MagicActionRow(
                            title: "Auto-Fix All Clips",
                            subtitle: "Batch process every clip in your timeline",
                            icon: "wand.and.stars.inverse",
                            color: .purple
                        ) {
                            // Process all
                            Task {
                                guard let project = appState.projectState.currentProject else { return }
                                for track in project.timeline.tracks {
                                    for clip in track.clips {
                                        await appState.projectState.performMagicFix(for: clip, options: appState.projectState.magicFixOptions)
                                    }
                                }
                            }
                        }
                        
                        MagicActionRow(
                            title: "Generate All Captions",
                            subtitle: "Create transcripts for the entire video",
                            icon: "captions.bubble.fill",
                            color: .blue
                        ) {
                            Task {
                                guard let project = appState.projectState.currentProject else { return }
                                for track in project.timeline.tracks {
                                    for clip in track.clips {
                                        _ = try? await appState.projectState.generateCaptions(for: clip)
                                    }
                                }
                            }
                        }
                        
                        MagicActionRow(
                            title: "Clean All Audio",
                            subtitle: "Remove silence and fillers globally",
                            icon: "waveform.path.badge.minus",
                            color: .orange
                        ) {
                            Task {
                                await appState.projectState.cleanProjectAudio()
                            }
                        }
                    }
                    
                    Spacer(minLength: 40)
                    
                    // QUICK TIPS
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Pro Tip", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundColor(.yellow)
                        
                        Text("Global Magic actions analyze your entire timeline to ensure consistency in color, audio levels, and caption styles.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Global Magic")
                .font(.title2.bold())
            Text("Orchestrate your entire project with AI.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Magic Action Row

struct MagicActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

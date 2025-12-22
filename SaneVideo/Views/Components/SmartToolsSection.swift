//
//  SmartToolsSection.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import AVFoundation

struct SmartToolsSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    
    @Binding var options: MagicFixOptions
    
    // We bind to the options from ProjectState parent, but simpler to just access via environment if we want
    // But adhering to pattern: usually sections take bindings or the clip.
    // Since options are in ProjectState, let's bind to them.
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Header & Presets
                headerView
                
                // MARK: - Action Card logic
                VStack(spacing: 16) {
                    // Audio Card
                    ToolCard(title: "Audio Cleanup", icon: "waveform", color: .blue) {
                        VStack(spacing: 12) {
                            InspectorToggle(
                                title: "Remove Silence",
                                subtitle: "Cut non-speech gaps",
                                isOn: $options.removeSilence,
                                icon: "waveform.slash"
                            )
                            
                            if options.removeSilence {
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Threshold")
                                                .font(.caption2)
                                            Spacer()
                                            Text("\(Int(options.silenceThreshold)) dB")
                                                .font(.caption2.monospacedDigit())
                                        }
                                        Slider(value: $options.silenceThreshold, in: -60 ... -20, step: 1)
                                            .tint(.blue)
                                    }
                                    .padding(.vertical, 4)
                                } label: {
                                    Text("Advanced Settings")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            InspectorToggle(
                                title: "Remove Fillers",
                                subtitle: "Cut 'um', 'uh', stutters",
                                isOn: $options.removeFillers,
                                icon: "bubble.left"
                            )
                            
                            InspectorToggle(
                                title: "Studio Sound",
                                subtitle: "AI voice enhancement",
                                isOn: $options.enhanceAudio,
                                icon: "mic.fill"
                            )
                        }
                    }

                    // Video Card
                    ToolCard(title: "Video & Framing", icon: "video", color: .purple) {
                        VStack(spacing: 12) {
                            InspectorToggle(
                                title: "Auto Color",
                                subtitle: "Light & color fix",
                                isOn: $options.autoEnhance,
                                icon: "paintpalette"
                            )
                            
                            InspectorToggle(
                                title: "Smart Crop (9:16)",
                                subtitle: "Auto vertical reframe",
                                isOn: $options.smartCrop,
                                icon: "iphone"
                            )
                            
                            InspectorToggle(
                                title: "Auto-Framing",
                                subtitle: "Track faces & focus",
                                isOn: $options.autoFraming,
                                icon: "target"
                            )
                        }
                    }

                    // Generative Card
                    ToolCard(title: "Generative AI", icon: "sparkles", color: .orange) {
                        VStack(spacing: 12) {
                            InspectorToggle(
                                title: "Magic Remove",
                                subtitle: "AI object removal",
                                isOn: $options.magicRemovePeople,
                                icon: "person.badge.minus"
                            )
                            
                            InspectorToggle(
                                title: "Cinematic Styles",
                                subtitle: "Prompt-based restyling",
                                isOn: $options.generativeStyle,
                                icon: "camera.filters"
                            )
                        }
                    }
                }

                // Global Action Button
                magicButton
                
                Text(String(localized: "smart_tools.footer.description", defaultValue: "One-click AI cleanup for your entire clip."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding(16)
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Magic Fix")
                    .font(.headline)
                Text("AI-Powered Polish")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button("Minimal Fix") { options = .minimal }
                Button("Pro Clean-up") { options = .proClean }
                Button("Social Media Ready") { options = .socialMedia }
            } label: {
                Label("Presets", systemImage: "wand.and.stars")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(6)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    private var magicButton: some View {
        Button {
            ServiceContainer.shared.hapticsManager.impact()
            Task {
                await appState.projectState.performMagicFix(for: clip, options: options)
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    if appState.projectState.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .bold))
                    }
                    
                    Text(appState.projectState.isProcessing ? 
                         (appState.projectState.processingStatus ?? "Processing...") : 
                         "Apply Super Magic Fix")
                        .fontWeight(.bold)
                }
                
                if appState.projectState.isProcessing && appState.projectState.processingProgress > 0 {
                    ProgressView(value: appState.projectState.processingProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.9))
                        .frame(height: 2)
                        .padding(.horizontal, 40)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                if appState.projectState.isProcessing {
                    Color.gray.opacity(0.5)
                } else {
                    Theme.Colors.accentGradient
                }
            }
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: Color.purple.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(appState.projectState.isProcessing)
    }
}

// MARK: - Visual Components

struct ToolCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let content: Content
    
    init(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 12, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            content
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// Reusing style from likely existing components or defining here for safety
private struct InspectorToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let icon: String
    var identifier: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
                .background(isOn ? Color.purple.opacity(0.1) : Color.gray.opacity(0.1))
                .foregroundColor(isOn ? .purple : .secondary)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier ?? "Toggle_\(title)")
                .scaleEffect(0.7)
                .padding(.trailing, -6)
        }
        .accessibilityIdentifier(identifier != nil ? "Row_\(identifier!.replacingOccurrences(of: "Toggle_", with: ""))" : "Row_\(title)")
    }
}

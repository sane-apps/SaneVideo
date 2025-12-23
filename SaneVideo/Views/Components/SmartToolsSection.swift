//
//  SmartToolsSection.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import AVFoundation

// Import new modifiers
// AnimationModifiers, AccessibilityModifiers

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
                                icon: "waveform.slash",
                                color: .blue,
                                identifier: "Toggle_RemoveSilence"
                            )
                            .help("Automatically cuts segments of the video where no speech is detected (Timeline Edit).")
                            
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
                                            .help("Audio levels below this threshold will be considered silence.")
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
                                icon: "bubble.left",
                                color: .blue,
                                identifier: "Toggle_RemoveFillers"
                            )
                            .help("Detects and removes hesitation words like 'um' and 'uh' from the timeline.")
                            
                            InspectorToggle(
                                title: "Enhance Speech",
                                subtitle: "Isolate voice & remove noise",
                                isOn: $options.enhanceAudio,
                                icon: "mic.fill",
                                color: .blue,
                                identifier: "Toggle_EnhanceSpeech"
                            )
                            .help("Applies EQ, Compression, and AI Voice Isolation to clean up background noise.")
                        }
                    }

                    // Video Card
                    ToolCard(title: "Video & Framing", icon: "video", color: .purple) {
                        VStack(spacing: 12) {
                            InspectorToggle(
                                title: "Auto Color",
                                subtitle: "Light & color fix",
                                isOn: $options.autoEnhance,
                                icon: "paintpalette",
                                color: .purple,
                                identifier: "Toggle_AutoColor"
                            )
                            .help("Automatically adjusts brightness, contrast, and saturation.")
                            
                            InspectorToggle(
                                title: "Smart Crop (9:16)",
                                subtitle: "Auto vertical reframe",
                                isOn: $options.smartCrop,
                                icon: "iphone",
                                color: .purple
                            )
                            .help("Reframes horizontal video to vertical (9:16) keeping the subject centered.")
                            
                            InspectorToggle(
                                title: "Auto-Framing",
                                subtitle: "Track faces & focus",
                                isOn: $options.autoFraming,
                                icon: "target",
                                color: .purple
                            )
                            .help("Keeps the subject centered in the frame even if they move.")
                        }
                    }

                    // Generative Card
                    ToolCard(title: "Generative AI", icon: "sparkles", color: .orange) {
                        VStack(spacing: 12) {
                            InspectorToggle(
                                title: "Magic Remove",
                                subtitle: "AI object removal",
                                isOn: $options.magicRemovePeople,
                                icon: "person.badge.minus",
                                color: .orange
                            )
                            .help("Automatically detects and removes people or distracting objects from the background.")
                            
                            InspectorToggle(
                                title: "Cinematic Styles",
                                subtitle: "Prompt-based restyling",
                                isOn: $options.generativeStyle,
                                icon: "camera.filters",
                                color: .orange
                            )
                            .help("Applies generative filters to give your video a specific look (e.g. 'Vintage', 'Cyberpunk').")
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
                    .accessibilityIdentifier("Preset_Minimal")
                Button("Pro Clean-up") { options = .proClean }
                    .accessibilityIdentifier("Preset_ProClean")
                Button("Social Media Ready") { options = .socialMedia }
                    .accessibilityIdentifier("Preset_SocialMedia")
            } label: {
                Label("Presets", systemImage: "slider.horizontal.3")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityIdentifier("PresetsMenu")
        }
    }

    private var magicButton: some View {
        Group {
            if appState.projectState.isProcessing {
                // OPTIMIZED: Use new LoadingIndicator component
                LoadingIndicator(
                    message: appState.projectState.processingStatus,
                    progress: appState.projectState.processingProgress
                )
                .transition(.smoothScale)
            } else {
                // Normal button
                Button {
                    ServiceContainer.shared.hapticsManager.impact()
                    Task {
                        await appState.projectState.performMagicFix(for: clip, options: options)
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 16, weight: .bold))
                            
                            Text("Apply Magic Fix")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.accentGradient)
                    .foregroundColor(Theme.Colors.accent.isLight() ? .black : .white)
                    .cornerRadius(12)
                    .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("MagicFixButton")
                .accessibilityLabel("Apply Magic Fix")
                .accessibilityHint("Automatically removes silence, filler words, and enhances your video. Keyboard shortcut: Command Shift M")
            }
        }
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
        .enhancedLiquidGlass(radius: 10, opacity: 0.3)
        .smoothAppear()
    }
}

// Reusing style from likely existing components or defining here for safety
private struct InspectorToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let icon: String
    var color: Color = .purple // Default for safety, but calls should override
    var identifier: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
                .background(isOn ? color.opacity(0.1) : Color.gray.opacity(0.1))
                .foregroundColor(isOn ? color : .secondary)
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
                .tint(color) // Match the section color
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier ?? "Toggle_\(title)")
                .scaleEffect(0.7)
                .padding(.trailing, -6)
        }
        .accessibilityIdentifier(identifier != nil ? "Row_\(identifier!.replacingOccurrences(of: "Toggle_", with: ""))" : "Row_\(title)")
    }
}

// Helper for contrast
extension Color {
    func isLight() -> Bool {
        // Simple heuristic for contrast text
        // In a real design system we'd check luminance
        // For standard Yellow/Cyan this is usually true, for Blue/Purple false
        return false // Defaulting to white text for now as most accents are dark enough or we want white on buttons
    }
}

// MARK: - Magic Progress Island

struct MagicProgressOverlay: View {
    let isProcessing: Bool
    let status: String?
    let progress: Double
    
    // Smooth animation namespace
    @Namespace private var namespace
    
    var body: some View {
        Group {
            if isProcessing {
                HStack(spacing: 16) {
                    // 1. Animated Icon
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.accent.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                            .symbolEffect(.bounce.up.byLayer, options: .repeating)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // 2. Status Text (Animated transition)
                        Text(status ?? "Processing...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText(value: 0))
                            .animation(.snappy, value: status)
                            .lineLimit(1)
                        
                        // 3. Progress Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(height: 4)
                                
                                Capsule()
                                    .fill(Theme.Colors.accentGradient)
                                    .frame(width: geo.size.width * CGFloat(progress), height: 4)
                                    .animation(.smooth(duration: 0.4), value: progress)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 4. Percentage text
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(width: 320)
                .background(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                )
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                // Use a standard transition instead of asymmetric which might be causing type-check issues if too complex
                .transition(.move(edge: .top).combined(with: .opacity)) 
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isProcessing)
        .padding(.top, 40) // Position nicely below toolbar
    }
}

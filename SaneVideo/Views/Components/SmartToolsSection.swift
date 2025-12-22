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
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Presets
            HStack {
                Text(String(localized: "smart_tools.presets.header", defaultValue: "PRESETS"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Menu {
                    Button(String(localized: "smart_tools.preset.minimal", defaultValue: "Minimal Fix")) { options = .minimal }
                        .accessibilityIdentifier("Preset_Minimal")
                    Button(String(localized: "smart_tools.preset.pro", defaultValue: "Pro Clean-up")) { options = .proClean }
                        .accessibilityIdentifier("Preset_Pro")
                    Button(String(localized: "smart_tools.preset.social", defaultValue: "Social Media Ready")) { options = .socialMedia }
                        .accessibilityIdentifier("Preset_Social")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text(String(localized: "smart_tools.presets.label", defaultValue: "Presets"))
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityIdentifier("PresetsMenu")
            }
            .padding(.bottom, -4)

            // MARK: - Audio Fixes
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "smart_tools.audio.header", defaultValue: "AUDIO"), systemImage: "waveform")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    InspectorToggle(
                        title: String(localized: "smart_tools.audio.remove_silence.title", defaultValue: "Remove Silence"),
                        subtitle: String(localized: "smart_tools.audio.remove_silence.subtitle", defaultValue: "Cut non-speech gaps"),
                        isOn: $options.removeSilence,
                        icon: "waveform.slash",
                        identifier: "smart_tools.audio.remove_silence"
                    )
                    
                    if options.removeSilence {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(localized: "smart_tools.audio.threshold", defaultValue: "Threshold"))
                                    .font(.caption2)
                                Spacer()
                                Text("\(Int(options.silenceThreshold)) dB")
                                    .font(.caption2.monospacedDigit())
                            }
                            Slider(value: $options.silenceThreshold, in: -60 ... -20, step: 1)
                                .tint(.purple)
                                .accessibilityIdentifier("smart_tools.audio.silence_threshold")
                        }
                        .padding(.leading, 36)
                    }
                    
                    InspectorToggle(
                        title: String(localized: "smart_tools.audio.remove_fillers.title", defaultValue: "Remove Fillers"),
                        subtitle: String(localized: "smart_tools.audio.remove_fillers.subtitle", defaultValue: "Cut 'um', 'uh', stutters"),
                        isOn: $options.removeFillers,
                        icon: "bubble.left",
                        identifier: "smart_tools.audio.remove_fillers"
                    )
                    
                    InspectorToggle(
                        title: String(localized: "smart_tools.audio.studio_sound.title", defaultValue: "Studio Sound"),
                        subtitle: String(localized: "smart_tools.audio.studio_sound.subtitle", defaultValue: "AI voice enhancement"),
                        isOn: $options.enhanceAudio,
                        icon: "mic.fill",
                        identifier: "smart_tools.audio.studio_sound"
                    )
                }
            }
            
            Divider()

            // MARK: - Video Fixes
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "smart_tools.video.header", defaultValue: "VIDEO & FRAMING"), systemImage: "video")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    InspectorToggle(
                        title: String(localized: "smart_tools.video.auto_color.title", defaultValue: "Auto Color"),
                        subtitle: String(localized: "smart_tools.video.auto_color.subtitle", defaultValue: "Light & color fix"),
                        isOn: $options.autoEnhance,
                        icon: "paintpalette",
                        identifier: "smart_tools.video.auto_color"
                    )
                    
                    InspectorToggle(
                        title: String(localized: "smart_tools.video.smart_crop.title", defaultValue: "Smart Crop (9:16)"),
                        subtitle: String(localized: "smart_tools.video.smart_crop.subtitle", defaultValue: "Auto vertical reframe"),
                        isOn: $options.smartCrop,
                        icon: "iphone",
                        identifier: "smart_tools.video.smart_crop"
                    )
                    
                    InspectorToggle(
                        title: String(localized: "smart_tools.video.auto_framing.title", defaultValue: "Auto-Framing"),
                        subtitle: String(localized: "smart_tools.video.auto_framing.subtitle", defaultValue: "Track faces & focus"),
                        isOn: $options.autoFraming,
                        icon: "target",
                        identifier: "smart_tools.video.auto_framing"
                    )

                    InspectorToggle(
                        title: String(localized: "smart_tools.video.highlight_cursor.title", defaultValue: "Highlight Cursor"),
                        subtitle: String(localized: "smart_tools.video.highlight_cursor.subtitle", defaultValue: "For screen recordings"),
                        isOn: $options.applyHighlightCursor,
                        icon: "cursorarrow.click.2",
                        identifier: "smart_tools.video.highlight_cursor"
                    )
                }
            }

            Divider()

            // MARK: - Generative Visuals
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "smart_tools.generative.header", defaultValue: "GENERATIVE VISUALS"), systemImage: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    InspectorToggle(
                        title: String(localized: "smart_tools.generative.magic_remove.title", defaultValue: "Magic Remove"),
                        subtitle: String(localized: "smart_tools.generative.magic_remove.subtitle", defaultValue: "AI object/people removal"),
                        isOn: $options.magicRemovePeople,
                        icon: "person.badge.minus",
                        identifier: "smart_tools.generative.magic_remove"
                    )
                    
                    InspectorToggle(
                        title: String(localized: "smart_tools.generative.cinematic_styles.title", defaultValue: "Cinematic Styles"),
                        subtitle: String(localized: "smart_tools.generative.cinematic_styles.subtitle", defaultValue: "Prompt-based restyling"),
                        isOn: $options.generativeStyle,
                        icon: "camera.filters",
                        identifier: "smart_tools.generative.cinematic_styles"
                    )
                }
            }

            Divider()

            // MARK: - Content Analysis
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "smart_tools.analysis.header", defaultValue: "AI ANALYSIS"), systemImage: "brain")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    InspectorToggle(
                        title: String(localized: "smart_tools.analysis.mood_grading.title", defaultValue: "Mood Grading"),
                        subtitle: String(localized: "smart_tools.analysis.mood_grading.subtitle", defaultValue: "Grade based on sentiment"),
                        isOn: $options.analyzeMood,
                        icon: "face.smiling",
                        identifier: "smart_tools.analysis.mood_grading"
                    )
                    
                    InspectorToggle(
                        title: String(localized: "smart_tools.analysis.scan_text.title", defaultValue: "Scan for Text"),
                        subtitle: String(localized: "smart_tools.analysis.scan_text.subtitle", defaultValue: "OCR analysis & indexing"),
                        isOn: $options.scanForText,
                        icon: "text.viewfinder",
                        identifier: "smart_tools.analysis.scan_text"
                    )
                    
                    InspectorToggle(
                        title: String(localized: "smart_tools.analysis.find_highlights.title", defaultValue: "Find Highlights"),
                        subtitle: String(localized: "smart_tools.analysis.find_highlights.subtitle", defaultValue: "Applause/Laughter detection"),
                        isOn: $options.findHighlights,
                        icon: "star.fill",
                        identifier: "smart_tools.analysis.find_highlights"
                    )
                }
            }
            
            Divider()
            
            // Action Button
            Button {
                ServiceContainer.shared.hapticsManager.impact()
                Task {
                    await appState.projectState.performMagicFix(for: clip, options: options)
                }
            } label: {
                VStack(spacing: 4) {
                    HStack {
                        if appState.projectState.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        
                        Text(appState.projectState.isProcessing ? 
                             (appState.projectState.processingStatus ?? String(localized: "smart_tools.status.processing", defaultValue: "Processing...")) : 
                             String(localized: "smart_tools.action.apply.title", defaultValue: "Apply Super Magic Fix"))
                            .fontWeight(.bold)
                    }
                    
                    if appState.projectState.isProcessing && appState.projectState.processingProgress > 0 {
                        ProgressView(value: appState.projectState.processingProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.8))
                            .frame(height: 2)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if appState.projectState.isProcessing {
                        Color.gray
                    } else {
                        Theme.Colors.accentGradient
                    }
                }
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(appState.projectState.isProcessing)
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "smart_tools.action.apply.title", defaultValue: "Apply Super Magic Fix"), key: "m", modifiers: [.command, .shift]))
            .accessibilityIdentifier("MagicFixButton")
            
            Text(String(localized: "smart_tools.footer.description", defaultValue: "One-click AI cleanup for your entire clip."))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
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

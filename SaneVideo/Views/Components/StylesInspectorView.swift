//
//  StylesInspectorView.swift
//  SaneVideo
//
//  Main inspector orchestrator. Sub-views extracted to:
//  - InspectorHelpers.swift (CollapsibleSection, SubsectionHeader, etc.)
//  - VideoSection.swift (Transform, Speed, Smart Crop)
//  - AudioSection.swift (Volume, Highlights, Analysis)
//  - CaptionsSection.swift (Style, OCR, Mood, ClipInfo, CursorEnhancements)
//

import SwiftUI

struct StylesInspectorView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?

    @AppStorage("inspectorProMode") private var isProMode = false // Default to Simple Mode
    
    // Collapsible section states
    @State private var showSmartTools = true
    @State private var showCaptions = true // Default open for visibility
    @State private var showVideo = false
    @State private var showBackground = false
    @State private var showEffects = false
    @State private var showAudio = false
    @State private var showClipInfo = false

    /// Does this clip have captions? (affects section priority)
    private var hasCaptions: Bool {
        selectedClip?.captions.isEmpty == false
    }

    var body: some View {
        @Bindable var projectState = appState.projectState
        
        VStack(spacing: 0) {
            // Header with Pro Mode Toggle
            HStack {
                InspectorHeader()
                Spacer()
                
                // Mode Toggle
                Picker("Mode", selection: $isProMode) {
                    Text("Simple").tag(false)
                    Text("Pro").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120) // Fixed width for stability
                .controlSize(.small)
                .padding(.trailing, 16)
                .help("Toggle between Simple (AI) and Pro (Manual) controls")
            }

            if let clip = selectedClip {
                ScrollView {
                    VStack(spacing: 0) {
                        // ═══════════════════════════════════════════
                        // PRIORITY 0: SMART TOOLS (Magic Fix)
                        // Always Visible
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Smart Tools",
                            icon: "wand.and.stars",
                            isExpanded: $showSmartTools
                        ) {
                            SmartToolsSection(clip: clip, options: $projectState.magicFixOptions)
                        }
                        
                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // PRIORITY 1: CAPTIONS
                        // Visible in Simple Mode IF captions exist (or if forced)
                        // Always visible in Pro Mode
                        // ═══════════════════════════════════════════
                        if isProMode || hasCaptions {
                            CollapsibleSection(
                                title: hasCaptions ? "Captions ✓" : "Captions",
                                icon: "captions.bubble",
                                isExpanded: $showCaptions,
                                badge: hasCaptions ? "\(clip.captions.count)" : nil
                            ) {
                                CaptionsSection(clip: clip)
                            }
                            
                            Divider().padding(.horizontal)
                        }

                        // ═══════════════════════════════════════════
                        // ADVANCED SECTIONS (Pro Mode Only)
                        // ═══════════════════════════════════════════
                        
                        if isProMode {
                            // PRIORITY 2: VIDEO
                            CollapsibleSection(title: "Video", icon: "film", isExpanded: $showVideo) {
                                VideoSection(clip: clip)
                            }

                            Divider().padding(.horizontal)

                            // PRIORITY 2.5: BACKGROUND
                            CollapsibleSection(
                                title: clip.backgroundEffect != nil ? "Background ✓" : "Background",
                                icon: "person.crop.rectangle",
                                isExpanded: $showBackground,
                                badge: clip.backgroundEffect != nil ? "On" : nil
                            ) {
                                BackgroundEffectsView(clip: clip)
                            }

                            Divider().padding(.horizontal)

                            // PRIORITY 3: EFFECTS
                            CollapsibleSection(
                                title: "Effects",
                                icon: "sparkles",
                                isExpanded: $showEffects,
                                badge: clip.effects.isEmpty ? nil : "\(clip.effects.count)"
                            ) {
                                EffectsPickerView(clip: clip)
                            }

                            Divider().padding(.horizontal)

                            // PRIORITY 4: AUDIO
                            CollapsibleSection(title: "Audio", icon: "waveform", isExpanded: $showAudio) {
                                AudioSection(clip: clip)
                            }

                            Divider().padding(.horizontal)

                            // PRIORITY 5: CLIP INFO
                            CollapsibleSection(title: "Clip Info", icon: "info.circle", isExpanded: $showClipInfo) {
                                ClipInfoSection(clip: clip)
                            }
                        } else {
                            // Simple Mode: Basic Adjustments
                            CollapsibleSection(
                                title: "Adjustments",
                                icon: "slider.horizontal.3", 
                                isExpanded: .constant(true)
                            ) {
                                HStack {
                                    Text("Rotation")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        withAnimation {
                                            appState.projectState.rotateClip(clip)
                                        }
                                    } label: {
                                        Label("Rotate 90°", systemImage: "rotate.right")
                                            .font(.body)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            
                            Divider().padding(.horizontal)

                            // Simple Mode Footer
                            Text("Switch to Pro Mode for manual video, audio, and effect controls.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 20)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }

                        // Cursor enhancements (screen recordings only) - Always useful
                        if clip.cursorDataURL != nil && isProMode {
                            Divider().padding(.horizontal)
                            CollapsibleSection(title: "Cursor", icon: "cursorarrow.rays", isExpanded: .constant(true)) {
                                CursorEnhancementsView(clip: clip)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            } else {
                EmptySelectionView()
            }
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        .background(.ultraThinMaterial)
    }
}

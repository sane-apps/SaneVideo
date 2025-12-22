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

    // Collapsible section states - ALL COLLAPSED BY DEFAULT for clean look
    // Order: Captions > Video > Effects > Audio > Clip Info (research-based priority)

    @State private var showSmartTools = true // Default open for visibility
    @State private var showCaptions = false
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
            InspectorHeader()

            if let clip = selectedClip {
                ScrollView {
                    VStack(spacing: 0) {
                        // ═══════════════════════════════════════════
                        // PRIORITY 0: SMART TOOLS (Magic Fix)
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
                        // PRIORITY 1: CAPTIONS (60%+ creators need this)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: hasCaptions ? "Captions ✓" : "Captions",
                            icon: "captions.bubble",
                            isExpanded: $showCaptions,
                            badge: hasCaptions ? "\(clip.captions.count)" : nil
                        ) {
                            CaptionsSection(clip: clip)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // PRIORITY 2: VIDEO (Transform, Speed, Crop)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(title: "Video", icon: "film", isExpanded: $showVideo) {
                            VideoSection(clip: clip)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // PRIORITY 2.5: BACKGROUND (Person Segmentation)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: clip.backgroundEffect != nil ? "Background ✓" : "Background",
                            icon: "person.crop.rectangle",
                            isExpanded: $showBackground,
                            badge: clip.backgroundEffect != nil ? "On" : nil
                        ) {
                            BackgroundEffectsView(clip: clip)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // PRIORITY 3: EFFECTS (High engagement - users test many)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Effects",
                            icon: "sparkles",
                            isExpanded: $showEffects,
                            badge: clip.effects.isEmpty ? nil : "\(clip.effects.count)"
                        ) {
                            EffectsPickerView(clip: clip)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // PRIORITY 4: AUDIO (Volume, Highlights)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(title: "Audio", icon: "waveform", isExpanded: $showAudio) {
                            AudioSection(clip: clip)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // PRIORITY 5: CLIP INFO (Rarely needed - collapsed)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(title: "Clip Info", icon: "info.circle", isExpanded: $showClipInfo) {
                            ClipInfoSection(clip: clip)
                        }

                        // Cursor enhancements (screen recordings only)
                        if clip.cursorDataURL != nil {
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

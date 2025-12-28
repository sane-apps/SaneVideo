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

    // UX FIX: All sections collapsed by default so users can see all available tools
    @AppStorage("inspector.showSmartTools") private var showSmartTools = false
    @AppStorage("inspector.showCaptions") private var showCaptions = false
    @AppStorage("inspector.showVideo") private var showVideo = false
    @AppStorage("inspector.showBackground") private var showBackground = false
    @AppStorage("inspector.showEffects") private var showEffects = false
    @AppStorage("inspector.showAudio") private var showAudio = false
    @AppStorage("inspector.showClipInfo") private var showClipInfo = false

    // CRITICAL FIX: Track if operation is in progress to prevent mode switching
    @State private var isOperationInProgress = false

    // CRITICAL FIX: Validate clip exists in current project
    private var validatedClip: VideoClip? {
        guard let clip = selectedClip,
              let project = appState.projectState.currentProject else {
            return nil
        }
        // CRITICAL FIX: Safely access timeline.tracks to prevent crash
        guard !project.timeline.tracks.isEmpty else {
            return nil
        }
        // Verify clip still exists in project
        for track in project.timeline.tracks where track.clips.contains(where: { $0.id == clip.id }) {
            // CRITICAL FIX: Get fresh clip from project to ensure we have latest state
            return track.clips.first(where: { $0.id == clip.id })
        }
        // Clip not found - auto-deselect
        return nil
    }

    /// Does this clip have captions? (affects section priority)
    private var hasCaptions: Bool {
        validatedClip?.captions.isEmpty == false
    }

    var body: some View {
        @Bindable var projectState = appState.projectState

        VStack(spacing: 0) {
            // UX FIX: Clean header without mode toggle - unified experience
            HStack {
                InspectorHeader()
                Spacer()
            }
            .padding(.trailing, 16)

            // CRITICAL FIX: Validate clip exists before rendering
            if let clip = validatedClip {
                ScrollView {
                    // CRITICAL FIX: Use LazyVStack for better performance with many sections
                    // P0 FIX: Add keyboard navigation support
                    LazyVStack(spacing: 0) {
                        // ═══════════════════════════════════════════
                        // PRIORITY 0: SMART TOOLS (Magic Fix)
                        // Always Visible
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Smart Tools",
                            icon: "wand.and.stars",
                            isExpanded: $showSmartTools
                        ) {
                            SmartToolsSection(clip: clip, options: $projectState.magicFixOptions, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // CAPTIONS (with badge if present)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: hasCaptions ? "Captions ✓" : "Captions",
                            icon: "captions.bubble",
                            isExpanded: $showCaptions,
                            badge: hasCaptions ? "\(clip.captions.count)" : nil
                        ) {
                            CaptionsSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // VIDEO (Transform, Speed, Crop)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(title: "Video", icon: "film", isExpanded: $showVideo) {
                            VideoSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // BACKGROUND (AI Replacement)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: clip.backgroundEffect != nil ? "Background ✓" : "Background",
                            icon: "person.crop.rectangle",
                            isExpanded: $showBackground,
                            badge: clip.backgroundEffect != nil ? "On" : nil
                        ) {
                            BackgroundEffectsView(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // EFFECTS (Filters, LUTs)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Effects",
                            icon: "sparkles",
                            isExpanded: $showEffects,
                            badge: clip.effects.isEmpty ? nil : "\(clip.effects.count)"
                        ) {
                            EffectsPickerView(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // AUDIO (Volume, EQ, Voice Isolation)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(title: "Audio", icon: "waveform", isExpanded: $showAudio) {
                            AudioSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // CLIP INFO (Metadata, Locate File)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(title: "Clip Info", icon: "info.circle", isExpanded: $showClipInfo) {
                            ClipInfoSection(clip: clip)
                        }

                    }
                    .padding(.bottom, 20)
                }
            } else {
                EmptySelectionView()
            }
        }
        // P1 FIX: Increase Inspector width for better spacing
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        .background(.ultraThinMaterial)
        // CRITICAL FIX: Auto-deselect if clip is deleted
        .onChange(of: appState.projectState.currentProject?.id) { _, _ in
            // CRITICAL FIX: Safely check if clip still exists
            if selectedClip != nil, validatedClip == nil {
                // Clip was deleted or project changed, deselect it
                selectedClip = nil
                AppLogger.general.info("Inspector: Auto-deselected deleted clip")
            }
        }
        // CRITICAL FIX: Sync selectedClip if it becomes invalid
        .onChange(of: selectedClip?.id) { _, _ in
            if selectedClip != nil, validatedClip == nil {
                // Selected clip doesn't exist, deselect
                selectedClip = nil
            }
        }
        // CRITICAL FIX: Monitor for operations in progress
        .onChange(of: appState.projectState.isProcessing) { _, isProcessing in
            isOperationInProgress = isProcessing
        }
    }
}

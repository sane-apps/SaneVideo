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

    // CRITICAL FIX: Persist collapsible section states
    @AppStorage("inspector.showSmartTools") private var showSmartTools = true
    @AppStorage("inspector.showCaptions") private var showCaptions = true
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
            // Header with Pro Mode Toggle
            HStack {
                InspectorHeader()
                Spacer()

                // CRITICAL FIX: Show mode indicator
                if isProMode {
                    Text("Pro")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }

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
                .help(isOperationInProgress ? "Cannot switch modes while an operation is in progress" : "Toggle between Simple (AI) and Pro (Manual) controls")
                .disabled(isOperationInProgress) // CRITICAL FIX: Prevent mode switch during operations
                .accessibilityLabel("Inspector Mode")
                .accessibilityHint(isOperationInProgress ? "Cannot switch modes while an operation is in progress" : "Switch between Simple mode for AI tools and Pro mode for manual controls")
                .accessibilityValue(isOperationInProgress ? "Operation in progress" : (isProMode ? "Pro Mode" : "Simple Mode"))
                .focusable() // P0 FIX: Keyboard navigation
            }

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
                                CaptionsSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                            }

                            Divider().padding(.horizontal)
                        }

                        // ═══════════════════════════════════════════
                        // ADVANCED SECTIONS (Pro Mode Only)
                        // ═══════════════════════════════════════════

                        if isProMode {
                            // PRIORITY 2: VIDEO
                            CollapsibleSection(title: "Video", icon: "film", isExpanded: $showVideo) {
                                VideoSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                            }

                            Divider().padding(.horizontal)

                            // PRIORITY 2.5: BACKGROUND
                            CollapsibleSection(
                                title: clip.backgroundEffect != nil ? "Background ✓" : "Background",
                                icon: "person.crop.rectangle",
                                isExpanded: $showBackground,
                                badge: clip.backgroundEffect != nil ? "On" : nil
                            ) {
                                BackgroundEffectsView(clip: clip, isOperationInProgress: $isOperationInProgress)
                            }

                            Divider().padding(.horizontal)

                            // PRIORITY 3: EFFECTS
                            CollapsibleSection(
                                title: "Effects",
                                icon: "sparkles",
                                isExpanded: $showEffects,
                                badge: clip.effects.isEmpty ? nil : "\(clip.effects.count)"
                            ) {
                                EffectsPickerView(clip: clip, isOperationInProgress: $isOperationInProgress)
                            }

                            Divider().padding(.horizontal)

                            // PRIORITY 4: AUDIO
                            CollapsibleSection(title: "Audio", icon: "waveform", isExpanded: $showAudio) {
                                AudioSection(clip: clip, isOperationInProgress: $isOperationInProgress)
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
                                        guard !clip.isMissing else {
                                            ServiceContainer.shared.toastManager.show(
                                                "Cannot rotate: Clip file is missing. Use 'Locate File' in Clip Info to relink the file.",
                                                type: .error
                                            )
                                            return
                                        }
                                        withAnimation {
                                            appState.projectState.rotateClip(clip)
                                        }
                                    } label: {
                                        Label("Rotate 90°", systemImage: "rotate.right")
                                            .font(.body)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(clip.isMissing)
                                    .help(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Rotate video 90 degrees clockwise")
                                    .accessibilityHint(clip.isMissing ? "Clip file is missing. Use 'Locate File' in Clip Info to relink the file." : "Rotate video 90 degrees clockwise")
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

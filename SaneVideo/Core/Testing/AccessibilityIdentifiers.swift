//
//  AccessibilityIdentifiers.swift
//  SaneVideo
//
//  Centralized registry of all accessibility identifiers.
//  This ensures compile-time safety and prevents tests from referencing
//  non-existent UI elements.
//
//  Usage in UI:
//    .accessibilityIdentifier(AccessibilityIdentifiers.recordButton)
//
//  Usage in Tests:
//    app.buttons[AccessibilityIdentifiers.recordButton]
//

import Foundation

/// Centralized registry of all accessibility identifiers.
///
/// **CRITICAL**: All UI elements must use identifiers from this enum.
/// All tests must reference identifiers from this enum.
///
/// Benefits:
/// - Compile-time safety: Renaming causes compiler errors everywhere
/// - Single source of truth: Change once, updates everywhere
/// - IDE autocomplete: Suggests available identifiers
/// - Refactoring support: Xcode can rename identifiers safely
/// - Type-safe: No string typos possible
enum AccessibilityIdentifiers {
    // MARK: - Mode Switching

    /// Toolbar button that switches between recording and editing modes
    static let modeSwitcher = "ModeSwitcherButton"

    // MARK: - Recording Controls

    /// Main record/stop button
    static let recordButton = "RecordButton"

    /// Recent clip button (appears after recording)
    static let recentClipButton = "RecentClipButton"

    /// Pause/resume recording button
    static let pauseRecordingButton = "PauseRecordingButton"

    /// Screen share toggle button
    static let screenShareToggle = "ScreenShareToggle"

    /// Camera toggle button
    static let cameraToggle = "CameraToggle"

    /// Microphone toggle button
    static let micToggle = "MicToggle"

    // MARK: - Editor Controls

    /// Export/share button in toolbar
    static let exportButton = "ExportButton"

    /// Split clip button
    static let splitClipButton = "SplitClipButton"

    /// Delete clip button
    static let deleteClipButton = "DeleteClipButton"

    /// Magic Fix button
    static let magicFixButton = "MagicFixButton"

    // MARK: - Inspector

    /// Inspector mode toggle (Simple/Pro)
    static let inspectorModeToggle = "InspectorModeToggle"

    /// Inspector toggle button (show/hide)
    static let inspectorToggle = "InspectorToggle"

    // MARK: - Sidebar

    /// Sidebar toggle button
    static let sidebarToggle = "SidebarToggle"

    // MARK: - PiP (Picture-in-Picture)

    /// PiP camera window
    static let pipCameraWindow = "PiPCameraWindow"

    /// PiP controls window (separate from camera window)
    static let pipControlsWindow = "PiPControlsWindow"

    // MARK: - Timeline

    /// Timeline clip view
    static let timelineClip = "TimelineClip"

    /// Timeline clip view (alternative identifier)
    static let timelineClipView = "TimelineClipView"

    /// Timeline empty state
    static let timelineEmptyState = "TimelineEmptyState"

    // MARK: - Export

    /// Export sheet
    static let exportSheet = "ExportSheet"

    /// Cancel export button
    static let cancelExportButton = "CancelExportButton"

    /// More options button in export sheet
    static let moreOptionsButton = "MoreOptionsButton"

    // MARK: - Magic Fix

    /// Magic Fix cancel button (shown during processing)
    static let magicFixCancelButton = "MagicFixCancelButton"

    /// Magic Fix progress overlay
    static let magicProgressOverlay = "MagicProgressOverlay"

    // MARK: - Presets

    /// Presets menu button
    static let presetsMenu = "PresetsMenu"

    /// Minimal preset button
    static let presetMinimal = "Preset_Minimal"

    /// Pro Clean preset button
    static let presetProClean = "Preset_ProClean"

    /// Social Media preset button
    static let presetSocialMedia = "Preset_SocialMedia"

    // MARK: - Smart Tools Toggles

    /// Remove silence toggle
    static let toggleRemoveSilence = "Toggle_RemoveSilence"

    /// Remove fillers toggle
    static let toggleRemoveFillers = "Toggle_RemoveFillers"

    /// Enhance speech toggle
    static let toggleEnhanceSpeech = "Toggle_EnhanceSpeech"

    /// Auto color toggle
    static let toggleAutoColor = "Toggle_AutoColor"

    // MARK: - Smart Tools Rows

    /// Remove silence row
    static let rowRemoveSilence = "Row_RemoveSilence"

    // MARK: - Onboarding

    /// Onboarding window
    static let onboardingWindow = "OnboardingWindow"

    /// Get Started button in onboarding
    static let onboardingGetStarted = "onboarding.action.get_started"

    /// Next button in onboarding
    static let onboardingNext = "onboarding.action.next"

    /// Back button in onboarding
    static let onboardingBack = "onboarding.action.back"

    /// Grant permissions button in onboarding
    static let onboardingGrantPermissions = "onboarding.action.grant_permissions"

    // MARK: - Windows

    /// Main application window
    static let mainWindow = "MainWindow"

    /// Settings window
    static let settingsWindow = "SettingsWindow"

    /// Project browser window
    static let projectBrowser = "ProjectBrowser"

    // MARK: - Other UI Elements

    /// Captions section
    static let captionsSection = "CaptionsSection"

    /// Play button
    static let playButton = "PlayButton"

    /// Pause button
    static let pauseButton = "PauseButton"

    // MARK: - Validation

    /// Validates that all identifiers are unique
    static func validate() -> [String] {
        let allIdentifiers = [
            modeSwitcher,
            recordButton,
            recentClipButton,
            pauseRecordingButton,
            screenShareToggle,
            cameraToggle,
            micToggle,
            exportButton,
            splitClipButton,
            deleteClipButton,
            magicFixButton,
            inspectorModeToggle,
            inspectorToggle,
            sidebarToggle,
            pipCameraWindow,
            pipControlsWindow,
            timelineClip,
            timelineClipView,
            timelineEmptyState,
            exportSheet,
            cancelExportButton,
            moreOptionsButton,
            magicFixCancelButton,
            magicProgressOverlay,
            presetsMenu,
            presetMinimal,
            presetProClean,
            presetSocialMedia,
            toggleRemoveSilence,
            toggleRemoveFillers,
            toggleEnhanceSpeech,
            toggleAutoColor,
            rowRemoveSilence,
            onboardingWindow,
            onboardingGetStarted,
            onboardingNext,
            onboardingBack,
            onboardingGrantPermissions,
            mainWindow,
            settingsWindow,
            projectBrowser,
            captionsSection,
            playButton,
            pauseButton
        ]

        // Check for duplicates
        let duplicates = allIdentifiers.filter { id in
            allIdentifiers.filter { $0 == id }.count > 1
        }

        return duplicates.unique()
    }

    /// Returns all identifiers as an array (for validation)
    static func all() -> [String] {
        [
            modeSwitcher,
            recordButton,
            recentClipButton,
            pauseRecordingButton,
            screenShareToggle,
            cameraToggle,
            micToggle,
            exportButton,
            splitClipButton,
            deleteClipButton,
            magicFixButton,
            inspectorModeToggle,
            inspectorToggle,
            sidebarToggle,
            pipCameraWindow,
            pipControlsWindow,
            timelineClip,
            timelineClipView,
            timelineEmptyState,
            exportSheet,
            cancelExportButton,
            moreOptionsButton,
            magicFixCancelButton,
            magicProgressOverlay,
            presetsMenu,
            presetMinimal,
            presetProClean,
            presetSocialMedia,
            toggleRemoveSilence,
            toggleRemoveFillers,
            toggleEnhanceSpeech,
            toggleAutoColor,
            rowRemoveSilence,
            onboardingWindow,
            onboardingGetStarted,
            onboardingNext,
            onboardingBack,
            onboardingGrantPermissions,
            mainWindow,
            settingsWindow,
            projectBrowser,
            captionsSection,
            playButton,
            pauseButton
        ]
    }
}

// MARK: - Array Extension

private extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

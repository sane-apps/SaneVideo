import Foundation

/// All UI elements and tests must use identifiers from this enum.
enum AccessibilityIdentifiers {
    // MARK: - Mode Switching

    /// Toolbar button that switches between recording and editing modes
    static let modeSwitcher = "ModeSwitcherButton"

    // MARK: - Recording Controls

    static let recordButton = "RecordButton"

    /// Recent clip button (appears after recording)
    static let recentClipButton = "RecentClipButton"

    static let pauseRecordingButton = "PauseRecordingButton"

    static let screenShareToggle = "ScreenShareToggle"

    static let cameraToggle = "CameraToggle"

    static let micToggle = "MicToggle"

    // MARK: - Editor Controls

    static let exportButton = "ExportButton"

    static let splitClipButton = "SplitClipButton"

    static let deleteClipButton = "DeleteClipButton"

    static let magicFixButton = "MagicFixButton"

    // MARK: - Inspector

    /// Inspector mode toggle (Simple/Pro)
    static let inspectorModeToggle = "InspectorModeToggle"

    static let inspectorToggle = "InspectorToggle"

    // MARK: - Sidebar

    static let sidebarToggle = "SidebarToggle"

    // MARK: - PiP (Picture-in-Picture)

    static let pipCameraWindow = "PiPCameraWindow"

    /// PiP controls window (separate from camera window)
    static let pipControlsWindow = "PiPControlsWindow"

    // MARK: - Timeline

    static let timelineClip = "TimelineClip"

    /// Timeline clip view (alternative identifier)
    static let timelineClipView = "TimelineClipView"

    static let timelineEmptyState = "TimelineEmptyState"

    // MARK: - Export

    static let exportSheet = "ExportSheet"

    static let cancelExportButton = "CancelExportButton"

    static let moreOptionsButton = "MoreOptionsButton"

    // MARK: - Magic Fix

    /// Magic Fix cancel button (shown during processing)
    static let magicFixCancelButton = "MagicFixCancelButton"

    static let magicProgressOverlay = "MagicProgressOverlay"

    // MARK: - Presets

    static let presetsMenu = "PresetsMenu"

    static let presetMinimal = "Preset_Minimal"

    static let presetProClean = "Preset_ProClean"

    static let presetSocialMedia = "Preset_SocialMedia"

    // MARK: - Smart Tools Toggles

    static let toggleRemoveSilence = "Toggle_RemoveSilence"

    static let toggleRemoveFillers = "Toggle_RemoveFillers"

    static let toggleEnhanceSpeech = "Toggle_EnhanceSpeech"

    static let toggleAutoColor = "Toggle_AutoColor"

    // MARK: - Smart Tools Rows

    static let rowRemoveSilence = "Row_RemoveSilence"

    // MARK: - Onboarding

    static let onboardingWindow = "OnboardingWindow"

    static let onboardingGetStarted = "onboarding.action.get_started"

    static let onboardingNext = "onboarding.action.next"

    static let onboardingBack = "onboarding.action.back"

    static let onboardingGrantPermissions = "onboarding.action.grant_permissions"

    // MARK: - Windows

    static let mainWindow = "MainWindow"

    static let settingsWindow = "SettingsWindow"

    static let projectBrowser = "ProjectBrowser"

    // MARK: - Other UI Elements

    static let captionsSection = "CaptionsSection"

    static let playButton = "PlayButton"

    static let pauseButton = "PauseButton"

    // MARK: - Validation

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

        let duplicates = allIdentifiers.filter { id in
            allIdentifiers.filter { $0 == id }.count > 1
        }

        return duplicates.unique()
    }

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

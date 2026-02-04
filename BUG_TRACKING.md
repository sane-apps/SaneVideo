# Bug Tracking

> **Template for new bugs at bottom of file**

---

## Active Issues

### File Size Violations
- **Status**: RESOLVED (2025-12-31)
- **Original Issue**: `Scripts/SaneMaster.rb` was 3861 lines, `generation.rb` was 792 lines
- **Resolution**: SaneMaster.rb refactored into 12 focused modules in `Scripts/sanemaster/`
  - All modules now under 500 lines (soft limit)
  - `generation.rb` split into: `generation.rb` (398), `generation_templates.rb` (171), `generation_mocks.rb` (208), `generation_assets.rb` (51)

### Swift File Size Warnings
Files approaching limits (monitor for refactoring):

| File | Lines | Status | Notes |
|------|-------|--------|-------|
| `Views/EditorLayoutView.swift` | ~600 | WARN | Consider extracting video/sidebar helpers |
| `State/ProjectState+ClipManagement.swift` | ~638 | WARN | Clip CRUD could be separate |
| `Windows/PiPCameraWindow.swift` | ~601 | WARN | Consider protocol extraction |
| `Services/Recording/RecordingEngine.swift` | ~576 | WARN | Source switching logic |

**Rule**: Soft 500 lines, Hard 800 lines. Split by responsibility.

### No-Audio-Track Clips Cut Entirely (Magic Fix)
- **Status**: FIXED (2026-01-31)
- **Symptom**: MagicFix on video-only files (no audio track) removes all content — clip becomes empty
- **Root Cause**: `SilenceDetector.detectSilence` returned `[CMTimeRange(start: .zero, duration: clip.duration)]` when no audio track found, treating the entire clip as silent
- **Fix**: Return `[]` (empty) when no audio track. Added `SilenceDetector.hasAudioTrack(url:)` pre-validation in `MagicFixService`. Also added margin (100ms padding) and tolerance (10% loud samples allowed) to improve cut quality.
- **Files**: `SilenceDetector.swift`, `MagicFixService.swift`, `MagicFixOptions.swift`, `ProjectState+SmartFeatures.swift`
- **Tests**: `SilenceDetectorTests.swift` (8 tests)

### Voice Isolation Hang (Magic Fix)
- **Status**: FIXED (2025-12-31)
- **Symptom**: Magic Fix stuck at 0% on "Starting Magic Fix..." - never progresses
- **Environment**: M4 Mac, macOS 15 (Sequoia), 20-second video
- **Root Causes** (two issues):
  1. `await player.scheduleSegment()` waits for playback completion, which never happens in offline/manual rendering mode
  2. `AUSoundIsolation` audio unit is incompatible with offline rendering mode
- **Fixes Applied**:
  1. Use `player.scheduleSegment(..., completionHandler: nil)` instead of async version
  2. Skip voice isolation in offline audio enhancement (it's for real-time playback only)
- **Files**: `Services/Audio/SaneAudioEnhancementService.swift`
- **Result**: Audio enhancement now completes in ~1 second (was hanging indefinitely)

### Incomplete UI Refactor - Version Mismatch
- **Status**: FIXED (2025-12-31)
- **Symptom**: Running app shows old UI (Video/Audio tabs) instead of new UI (Media/Transcript/Projects tabs)
- **Root Cause**: UI refactor was partially done but NEVER COMMITTED to git:
  - `CaptionsSection.swift` - Simplified to quick access (uncommitted)
  - `TranscriptionEditorView.swift` - Became "Unified Captions Hub" (uncommitted)
  - `SidebarView.swift` - NOT changed (Magic Fix still on left)
  - `StylesInspectorView.swift` - NOT changed (Captions still on right)
- **Intended Refactor**:
  1. Move full caption editing from RIGHT inspector → LEFT sidebar (Transcript tab)
  2. Remove Magic Fix button from LEFT sidebar Quick Actions
  3. Simplify Captions section in RIGHT inspector to quick-access only
- **Fix Applied**: Complete the refactor and commit all changes
- **Files**: `SidebarView.swift`, `StylesInspectorView.swift`, `CaptionsSection.swift`, `TranscriptionEditorView.swift`

### Screen Recording Permission Dialog Regression
- **Status**: FIXED (2025-12-31)
- **Symptom**: Permission dialog appears on every clean build despite permission being granted
- **Root Cause**: `CGPreflightScreenCaptureAccess()` returns false even when permission is granted (macOS quirk)
- **Fix Applied**: Persist `screenRecordingEverGranted` flag in UserDefaults when capture succeeds, check it before re-requesting
- **Files**: `Services/Permissions/PermissionManager.swift`, `Services/Recording/ScreenRecorder.swift`

### Recording Ignores User Resolution/FPS (Unnecessary Scaling)
- **Status**: FIXED (2026-01-10)
- **Symptom**: Screen recordings captured at 1080p@60 and recordings encoded at 1080p regardless of `UserPreferences.recordingResolution` / `recordingFPS`, causing unnecessary scaling and CPU work.
- **Root Cause**: `ScreenRecorder` and `VideoWriter` used hardcoded `targetSize`, and `ScreenRecorder` used hardcoded 60fps.
- **Fix Applied**: `RecordingEngine` now reads recording prefs once at start (and re-applies on screen switches), sets `ScreenRecorder.targetSize/targetFrameRate`, and constructs `VideoWriter` with the preferred `targetSize`.
- **Files**: `Services/Recording/RecordingEngine.swift`, `Services/Recording/RecordingEngine+Lifecycle.swift`, `Services/Recording/ScreenRecorder.swift`, `Services/Recording/VideoWriter.swift`

### Project File Corruption
- **Status**: FIXED (2025-12-31)
- **Last Occurrence**: 2025-12-30 (specific file: 3054218B-9F22-439E-A9FC-D2980ED22749.svproj)
- **Root Cause**: Corrupted `.svproj` files with invalid JSON remained in the projects folder, causing error toast on every app launch
- **Applied Fixes** (in `Services/Project/ProjectStore.swift`):
  1. JSON structure validation on save (atomic write + verify decode)
  2. Backup creation before overwrite (`.svproj.backup`)
  3. Enhanced error logging to distinguish "missing" vs "corrupted"
  4. Automatic backup recovery when main file is corrupted
  5. **NEW**: `quarantineCorruptedFile()` function (lines 382-415) - moves corrupted files to `.quarantine/` folder with timestamp, prevents repeated error toasts
  6. Silent skip for missing files (no error toast for deleted files)
- **Verification** (2025-12-31):
  - All 11 current `.svproj` files validated as valid JSON
  - The specific corrupted file (3054218B) is no longer present (quarantined or deleted)
  - No `.quarantine/` directory exists (no recent quarantines)
  - 176 legacy `.sanevideoproject` files exist but are ignored by ProjectStore (only loads `.svproj`)
- **Architecture Note**: Two file extensions in use:
  - `.svproj` - Local project files (loaded by ProjectStore)
  - `.sanevideoproject` - iCloud sync/backup files (managed by SyncManager)

### Audio/Video Timeline Desync After Magic Fix
- **Status**: FIXED (2025-12-31)
- **Symptom**: Video and audio playhead completely out of sync after running Magic Fix
- **Root Cause**: `AudioTrackBuilder` used enhanced audio file's duration for segment timing, but enhanced audio may have slightly different duration than original video due to 44100Hz AAC encoding. The `removedRanges` are defined in original video timing, causing cumulative drift.
- **Fix Applied**: Use `clip.duration` (original video duration) for segment timing in AudioTrackBuilder, not the enhanced audio's duration
- **Files**: `Core/Engine/AudioTrackBuilder.swift:44-49`
- **Update (2026-01-08)**:
  - `SaneAudioEnhancementService` now preserves source sample rate when writing enhanced audio (prevents duration drift).
  - `AudioTrackBuilder` now validates enhanced-audio duration vs `clip.duration` and falls back to original audio if mismatched (prevents desync/missing-audio edge cases).

### Smooth Jump Cuts Cause Perceived A/V Drift (Magic Fix)
- **Status**: FIXED (2026-01-08)
- **Symptom**: After running Magic Fix (default includes **Smooth Cuts**), audio feels “late/early” around jump cuts, especially after multiple silence/filler removals.
- **Root Cause**:
  1. Video path applied an internal overlap window for smooth cuts, but audio path did not mirror that overlap/crossfade, so the visual transition timing diverged from the audio timing at cut boundaries.
  2. Video overlap math treated the overlap as a fixed time in composition while also time-scaling segments, which makes overlap durations inconsistent when `clip.speed != 1.0`.
- **Fix Applied**:
  - Centralized overlap math in `TimeUtils.smoothCutOverlap(clipSpeed:)` (played-time overlap + speed-scaled source-time overlap).
  - Updated `VideoTrackBuilder` to clamp overlap to trimStart and use the correct played/source mapping (speed-safe).
  - Updated `AudioTrackBuilder` to apply the same overlap window and crossfade across internal smooth cuts, keeping A/V aligned.
- **Files**: `Core/Utilities/TimeUtils.swift`, `Core/Engine/VideoTrackBuilder.swift`, `Core/Engine/AudioTrackBuilder.swift`
- **Regression Test**: `SaneVideoTests/Regression/MagicFixRegressionTests.swift:testSmoothCutOverlapScalesWithSpeed`

### Captions Not Showing in Transcript Tab
- **Status**: FIXED (2025-12-31)
- **Symptom**: Magic Fix generates captions successfully, but Transcript sidebar tab shows empty state
- **Root Cause**: `TranscriptionEditorView` used `@Binding var selectedClip` which pointed to a stale copy. When captions were updated via `ProjectState.applyCaptions()`, the binding wasn't refreshed.
- **Fix Applied**: Added `currentClip` computed property that fetches fresh clip from project by ID (matches pattern in `StylesInspectorView.validatedClip`)
- **Files**: `Views/Components/TranscriptionEditorView.swift:19-35`

### Duplicate Toast Notifications
- **Status**: FIXED (2025-12-31)
- **Symptom**: Multiple duplicate toast notifications appearing during Magic Fix operations
- **Root Cause**: Both `ProjectState+Analysis.swift` and `ProjectState+Audio.swift` were showing toasts for the same events (transcription start, progress)
- **Fix Applied**: Removed redundant toasts, keep only `processingStatus` for progress updates (reduces notification spam)
- **Files**: `State/ProjectState+Analysis.swift:229-252`, `State/ProjectState+Audio.swift:259`

### GlobalHotkeyManager Memory Leak
- **Status**: FIXED (2025-12-31)
- **Symptom**: GlobalHotkeyManager never deallocates, event handlers remain active after window closes
- **Root Cause**: `Unmanaged.passRetained(self)` at line 32 increments retain count, but deinit never calls `retainedSelf?.release()` to balance it
- **File(s)**: `Core/GlobalHotkeyManager.swift:32, 113-116`
- **Fix Applied**: Added `retainedSelf?.release()` in deinit before `RemoveEventHandler`

### Audio Click on Short Clips (0.05-0.15s)
- **Status**: FIXED (2025-12-31)
- **Symptom**: Audible click/pop at the end of short audio clips
- **Root Cause**: Fade-out logic at line 104 only applies if `playDuration > 3 * fadeDuration (0.15s)`. Clips between 0.05-0.15s get fade-in but NO fade-out, causing abrupt cutoff.
- **File(s)**: `Core/Engine/AudioTrackBuilder.swift:104-111, 222-237`
- **Fix Applied**: Changed threshold from 3x to 2x fadeDuration, added proportional fade-out calculation for clips just above threshold. Now clips > 0.10s get proper fade-out.
- **Regression Test**: `SaneVideoTests/Regression/AudioClickRegressionTests.swift`

### ServiceContainer Synchronous Init (Startup Bottleneck)
- **Status**: ARCHITECTURAL DEBT (2025-12-31)
- **Symptom**: Slow app launch, memory spike on first ServiceContainer access
- **Root Cause**: `private init()` at lines 123-205 initializes **40+ services synchronously**. First access to ANY service (even just permissions) loads VisionOrchestrator, CameraManager, ALL ML services.
- **File(s)**: `Core/DI/ServiceContainer.swift:123-205`
- **Fix Required**: Lazy initialization - only initialize services when first accessed

### ControlsKit UI/Architecture Coupling
- **Status**: ARCHITECTURAL DEBT (2025-12-31)
- **Symptom**: SwiftUI Previews crash or hang for any view using IconCircleButton
- **Root Cause**: `IconCircleButtonStyle` directly accesses `ServiceContainer.shared.hapticsManager` at lines 157, 162. UI component depends on global service container.
- **File(s)**: `Core/ControlsKit.swift:157, 162`
- **Fix Required**: Inject haptics via environment or make it optional for previews

### Project File Corrupted Toast on Launch
- **Status**: FIXED (2025-12-31)
- **Screenshot**: Screenshot 2025-12-31 at 6.05.41 PM.png
- **Symptom**: Toast shows "Project file corrupted: 3054218B-9F22-439E-A9FC-D2980ED22749.svproj" on app launch
- **Root Cause**: A `.svproj` file existed on disk but contained invalid JSON. After showing the corrupted toast, the file remained in place, causing the toast to reappear on every launch.
- **File(s)**: `Services/Project/ProjectStore.swift:382-415`
- **Fix Applied**: Added `quarantineCorruptedFile()` function that moves corrupted files to `.quarantine/` folder after showing the error toast. This prevents repeated toasts on subsequent launches. Files are moved (not deleted) so users can attempt manual recovery if needed.
- **Note**: Missing files (file doesn't exist) are already handled gracefully and silently skipped (line 101-106).

### Pipeline Audit Fixes (2025-12-31)
- **Status**: FIXED (2025-12-31)
- **Origin**: Pipeline audit "Fix-these-first" claims verified and fixed

#### P0: Privacy Blur Leaks Across Clips
- **Symptom**: Privacy blur regions from one clip appear on adjacent clips
- **Root Cause**: Privacy regions weren't filtered by composition time in SaneVideoCompositor
- **Fix Applied**: Added `where range.containsTime(request.compositionTime)` filter
- **File**: `Core/Rendering/SaneVideoCompositor.swift:210`

#### P0: Wrong Clip Transform Selection
- **Symptom**: Transform from wrong clip applied, causing incorrect positioning/scaling
- **Root Cause**: `.first(where:)` found matching trackID but not for correct time range
- **Fix Applied**: Iterate and use `getTransformRamp(for: request.compositionTime)` to find valid instruction
- **File**: `Core/Rendering/SaneVideoCompositor.swift:218-230`

#### P1: Enhanced Audio Temp File Cleanup
- **Symptom**: Enhanced audio URL persisted in project but temp file deleted, causing playback errors
- **Root Cause**: Project hydration didn't validate enhancedAudioURL existence
- **Fix Applied**: Added validation in `hydrateProject()` - clears URL if file missing, falls back to original
- **File**: `Services/Project/ProjectFileManager.swift:297-305`

#### P1: 4K Export Transform Mismatch
- **Symptom**: 4K exports have incorrect transforms baked at 1080p resolution
- **Root Cause**: `CompositionBuilder.build()` hardcoded 1080p renderSize, not export resolution
- **Fix Applied**: Added `renderSize` parameter, `ExportCompositor` now passes export resolution
- **Files**: `Core/Engine/CompositionBuilder.swift:26`, `Services/Export/ExportCompositor.swift:17-19`

#### P2: Semantic Gating Mis-timed
- **Symptom**: Gating (mute non-speech) regions applied at wrong times after cuts
- **Root Cause**: Gating computed per-segment instead of once per clip, file time not mapped to composition time
- **Fix Applied**: Pre-compute gating once per clip, map file time to composition time with speed scaling
- **File**: `Core/Engine/AudioTrackBuilder.swift:57-61, 123-184`

#### P2: Batch Magic Fix Cancel/Undo Confusion
- **Symptom**: Cancel only stops latest operation, undo creates many small entries
- **Root Cause**: Each `performMagicFix` created own undo group and overwrote `currentProcessingTask`
- **Fix Applied**: Added `isBatchOperation` flag - batch uses single "Magic Fix All" undo group
- **Files**: `State/ProjectState+SmartFeatures.swift:92-113, 262-266`, `State/ProjectState+Timeline.swift:203-206, 223`

---

### Pipeline Audit - Additional Findings (2026-01-01)

#### P2: Waveform vs Enhanced Audio Mismatch
- **Status**: FIXED (2026-01-08)
- **Symptom**: Waveform visualization shows original audio, but playback/export uses enhanced audio (if available)
- **Root Cause**: `WaveformService.generateWaveform()` uses `clip.url` only (line 94), but `AudioTrackBuilder` uses `clip.enhancedAudioURL ?? clip.url` (line 38)
- **Impact**: UI shows waveform for original audio, but user hears enhanced audio → confusing mismatch
- **Files**: `Services/Audio/WaveformService.swift:94`, `Core/Engine/AudioTrackBuilder.swift:38`
- **Fix Applied**:
  - WaveformService now selects the same audio source as playback/export (enhanced audio when duration-aligned).
  - Cache now invalidates automatically when the chosen audio URL changes (prevents stale waveforms after enhancement).
  - If enhanced audio duration is mismatched, both waveform + playback fall back to original audio to avoid drift.

#### P3: Sample Rate Assumptions Across App
- **Status**: ARCHITECTURAL DEBT
- **Observation**: Mixed sample rate assumptions (48k for recording/system audio, some 44.1k defaults in offline paths)
- **Potential Impact**: Subtle A/V drift, duration mismatches, gating window misalignment
- **Files**: `Services/Recording/VideoWriter.swift`, `Services/Recording/ScreenRecorder.swift`, `Services/Audio/SaneAudioEnhancementService.swift`, `Services/Audio/WaveformService.swift:126`
- **Update (2026-01-08)**: `SaneAudioEnhancementService` now preserves the source sample rate when writing enhanced AAC to keep durations aligned.
- **Update (2026-01-10)**: Recording/export paths standardized on 48k where possible (mic resampled to 48k for writing; ExportEngine AAC output set to 48k).
- **Fix Required**: Continue audit/standardization (WaveformService still needs to mirror enhanced-audio selection).

#### P3: Multiple Export Implementations Divergence Risk
- **Status**: MONITOR
- **Observation**: `ExportEngine` (AVAssetReader/Writer) and `BatchExportService` (AVAssetExportSession) both use `ExportCompositor`, but could diverge if one is modified
- **Potential Impact**: "Export A looks different than Export B" if implementations drift
- **Files**: `Services/Export/ExportEngine.swift`, `Services/Export/BatchExportService.swift`, `Services/Export/ExportCompositor.swift`
- **Fix Required**: Ensure both paths use same composition/transform logic (currently both use ExportCompositor, so risk is low)

#### P3: NotificationCenter Magic Fix Triggers (Multi-Window Risk)
- **Status**: MONITOR
- **Observation**: Magic Fix triggered via `NotificationCenter` ("TriggerMagicFix", "TriggerMagicFixAll"). Multiple views/windows subscribe
- **Potential Impact**: If multiple windows exist, same operation could run multiple times
- **Files**: `SaneVideoApp.swift:109`, `Views/EditorLayoutView.swift:95, 108`, `Views/SidebarView.swift:34`
- **Fix Required**: Verify if ProjectState operations are idempotent or add guard to prevent duplicate execution

---

### No Audio on Playback (Volume = 0)
- **Status**: FIXED (2025-12-31)
- **Symptom**: Recording captures audio (verified with ffprobe: aac, 48kHz, 2 channels), but playback is silent
- **Root Causes Identified**:
  1. `RealTimeAudioProcessor` (commit 1be93b5, Dec 24) sets `videoPlayer.volume = 0.0` during recording, never restores it
  2. `AudioLimiter` MTAudioProcessingTap (commit 6dededa, Dec 31) is not compatible with AVPlayer playback
- **Fixes Applied**:
  - **Primary Fix**: Bypassed `AudioLimiter.applyLimiter()` in `CompositionBuilder.swift:131`
    - MTAudioProcessingTap only works reliably for export, not AVPlayer playback
  - Added diagnostic logging for clip volume in `AudioTrackBuilder.swift:84`
  - Previous fix: `newPlayer.volume = 1.0` in `PlaybackState.setupPlayer()` at line 252
- **Files**: `Core/Engine/CompositionBuilder.swift:131`, `Core/Engine/AudioTrackBuilder.swift:84`, `State/PlaybackState.swift:252`
- **User Verified**: "very good I can hear the audio again!"
- **Regression Test**: `SaneVideoTests/Regression/AudioPlaybackRegressionTests.swift`

### Test Isolation - Toast During Tests
- **Status**: FIXED (2025-12-31)
- **Symptom**: Tests for corrupted project recovery were triggering production toast notifications
- **Root Cause**: `ProjectStore.swift` showed toasts on corrupted files without checking for test mode
- **Fix Applied**: Added `isInTestMode` property to ProjectStore, guard toast calls with `if !self.isInTestMode`
- **Files**: `Services/Project/ProjectStore.swift:14, 19, 37, 52, 219-223, 231-235`

### Test Stale - MagicFixOptions Preset
- **Status**: FIXED (2025-12-31)
- **Symptom**: 2 test failures in MagicFixServiceTests for "Pro Clean preset has expected values"
- **Root Cause**: Test expected `autoEnhance=true, findHighlights=true` but preset was updated to `false` for both (2025-12-31 simplification to 5 core features)
- **Fix Applied**: Updated test to match current preset values
- **Files**: `SaneVideoTests/MagicFixServiceTests.swift:507-517`

### Recording Frame Rate Drops to 15fps
- **Status**: PARTIALLY FIXED (2025-12-31) - Portrait filter fixed, hardware limitation remains
- **Symptom**: Video recorded at 15fps despite user preference set to 30/60fps (default is 60fps)
- **Investigation Results** (2025-12-31):
  - Camera hardware only supports **30fps max** at 1080p (not 60fps)
  - Log: `Current format: 1920x1080 @ 30fps (max: 30fps)` - camera physically cannot do 60fps
  - Yet CameraFramePublisher only receives ~15fps from hardware
- **Root Causes**:
  1. **FIXED**: Commit 626956d (Dec 25) - format selection only on initial session creation
  2. **FIXED**: Portrait filter was removing ALL formats (Mac Studio camera only has portrait-capable formats)
     - All 7 formats had `isPortraitEffectSupported = true`
     - Filter removed ALL formats, forcing preset fallback which ignores frame duration settings
     - Fix: Check `isPortraitEffectEnabled` (device active state) instead of `isPortraitEffectSupported` (format capability)
  3. **REMAINING**: Mac Studio FaceTime HD camera delivers ~15fps despite 30fps configuration
     - Format correctly selected: 1920x1080 @ 30fps
     - Frame duration correctly set: `activeVideoMinFrameDuration = 1/30`
     - Hardware still delivers only ~15fps - may be hardware/driver limitation
- **Fixes Applied**:
  - Removed `isPortraitEffectSupported` filter - now uses all camera formats
  - Format selection now works correctly (not falling back to preset)
  - Added diagnostic logging in `CameraFramePublisher.swift`
- **Files**:
  - `Services/Camera/CameraManager.swift:408-420, 561-575` (portrait filter removed)
  - `Services/Camera/CameraFramePublisher.swift:16-52` (FPS tracking diagnostics)
- **Next Steps**:
  - Test on different Mac hardware to confirm if 15fps is Mac Studio specific
  - Investigate if Center Stage or other camera effects are reducing frame rate
  - Check System Preferences > Camera for any active effects

---

### Audio/Video Playback Desync (Lag)
- **Status**: FIXED (2025-12-31)
- **Symptom**: Noticeable lag between video and audio during playback, even before any Magic Fix processing
- **Root Cause**: **DUAL AUDIO PLAYBACK ARCHITECTURE FLAW**
  1. `AVPlayer` plays composition audio (from CompositionBuilder with AudioTrackBuilder)
  2. `RealTimeAudioProcessor` plays SAME audio via AVAudioEngine simultaneously
  3. `setupForPlayerItem()` called in `Task {}` WITHOUT await - race condition
  4. `videoPlayer.volume = 0.0` happens async AFTER engine starts - brief double audio
  5. No playback rate sync - `setPlaybackRate()` only affects video, not audio engine
- **Fix Applied**: Disabled `RealTimeAudioProcessor` entirely in `PlaybackState.swift`
  - Commented out setup, play, pause, seek, and cleanup calls
  - Audio now comes from composition only (properly synced with video)
  - Effects still applied during export via AudioMix
- **Files**: `State/PlaybackState.swift:255-274, 303-305, 353-354, 360-361, 375-376`
- **TODO**: Re-implement RealTimeAudioProcessor properly with single audio source architecture

### Recording Disappears (Error -16364)
- **Status**: FIXED (2025-12-31)
- **Symptom**: Recording a video results in it "disappearing" - doesn't launch into editor, toast shows "Recording cancelled or empty"
- **Root Cause**: `AVAssetWriter` error -16364 ("invalid timestamp") caused by timestamp discontinuities during screen recording with presenter overlay. macOS 14+ can cause timestamps to go backwards when presenter overlay toggles on/off.
- **Fix Applied**: Added monotonic timestamp enforcement in `VideoWriter.swift`:
  - Track `lastWrittenVideoTime`, `lastWrittenMicTime`, `lastWrittenSystemAudioTime`
  - Drop frames with timestamps <= last written time (prevents -16364)
  - Log warning if too many frames are dropped
- **Files**: `Services/Recording/VideoWriter.swift`
- **Reference**: [Apple Developer Forums - Presenter overlay causes AVAssetWriter failure](https://developer.apple.com/forums/thread/738846)

### UI Feature Duplication
- **Status**: FIXED (2025-12-31)
- **Symptom**: Same features appearing in multiple places (Smart Crop in 3 places, Find Highlights in 2 places, Auto-Framing in 2 places)
- **Root Cause**: Organic feature growth without consolidation
- **Fix Applied**:
  - Magic Fix simplified to 5 core features (Remove Silence, Remove Fillers, Generate Captions, Enhance Speech, Smooth Cuts)
  - Removed duplicates from ClipContextMenu (Smart Crop, Auto-Framing, Find Highlights)
  - TranscriptionEditorView expanded as PRIMARY captions location with style picker
  - CaptionsSection simplified to redirect to Transcript sidebar tab
- **Canonical Locations**:
  - Smart Crop, Auto-Framing → VideoSection
  - Find Highlights → AudioSection
  - Caption Styling → TranscriptionEditorView (sidebar)
  - Core Cleanup → SmartToolsSection (Magic Fix)

---

## Swift 6 Modernization

### @preconcurrency Imports (11 files)
Apple frameworks not yet Sendable-annotated. Remove when Apple updates:

| Framework | Files Using |
|-----------|-------------|
| AVFoundation | PlaybackState, SaneVideoCompositor, AudioService, VoiceIsolation, CameraManager, AudioResampler, CameraFramePublisher |
| ScreenCaptureKit | ScreenRecorderProtocol, ScreenRecorder+Delegates, ScreenRecorder |
| Combine | CameraConcurrencyRegressionTests |

**When to check**: Each Xcode major release
**Last audited**: 2025-12-31

---

## Sparkle Auto-Update

**Status**: Configured (2025-12-31)

| Item | Status |
|------|--------|
| EdDSA key pair | Generated |
| Public key in Info.plist | Configured |
| Private key | In macOS Keychain |
| Appcast URL | https://www.sanevideo.app/appcast.xml |
| Auto-check enabled | No (manual only) |

**Before Release**:
- [ ] Set up appcast.xml on server
- [ ] Sign updates with `sign_update` tool
- [ ] Consider enabling auto-check (`startingUpdater: true`)

---

## Infrastructure Fixes (2026-01-02)

Tooling improvements to prevent recurring friction across SaneBar and SaneVideo:

### INFRA-001: Stale Diagnostics Logs

**Root Cause**: `find_app_log()` in `diagnostics.rb` searched entire `@diagnostics_dir` with `**` glob, picking up historical exports instead of current one.

**Fix**:
- Changed to accept `export_path` parameter and scope search to current export only
- Added `cleanup_old_exports()` to keep only last 3 diagnostic exports
- Made diagnostics.rb project-aware using `project_name` method

**Files**: `Scripts/sanemaster/diagnostics.rb:38-47, 159-164`

---

### INFRA-002: Stale Build Detection

**Root Cause**: Could launch old app binary after source changes without rebuilding.

**Fix**: Added stale build detection to `launch_app()`:
- Compares binary mtime vs newest source file mtime
- Auto-rebuilds if stale (unless `--force` flag)
- Made test_mode.rb project-aware using `project_name` method

**Files**: `Scripts/sanemaster/test_mode.rb:17-47`

---

### INFRA-003: Project-Aware Tooling

**Root Cause**: Hardcoded "SaneBar"/"SaneVideo" strings required maintaining separate file versions.

**Fix**: Added `project_name` method that detects from current directory (`File.basename(Dir.pwd)`):
- Diagnostics directory: `#{project_name}_Diagnostics`
- Crash file globs: `#{project_name}-*.ips`
- DerivedData paths: `#{project_name}-*/...`
- Process names for `log` command: `process == "#{project_name}"`

**Result**: Both `diagnostics.rb` and `test_mode.rb` are now identical in both projects.

---

## Resolved Sessions

<details>
<summary>2025-12-29 Session (click to expand)</summary>

All items resolved:
- Unified toolbar implemented
- Layout collapse bugs fixed
- Background color consistency fixed
- Ruler label visibility fixed
- ExportEngine Sendable warning fixed

</details>

<details>
<summary>2025-12-28 Session (click to expand)</summary>

All items resolved:
- Crosshair regression fixed
- Effect preview thumbnails fixed
- Magic Fix hang fixed
- PrivacyBadge position fixed
- Orphaned lock/mute icons fixed

</details>

---

## Completed (Jan 31 - Feb 3, 2026)

### Silence Detection No-Audio Bug + Quality Improvements
- **Status**: FIXED (2026-01-31)
- **Symptom**: `SilenceDetector.detectSilence` returned the entire clip as silent when no audio track existed, causing MagicFix to remove all content from video-only files
- **Root Cause**: Missing validation for audio track presence before silence detection
- **Fixes Applied**:
  1. Return empty array `[]` when no audio track detected (instead of treating entire clip as silent)
  2. Added `SilenceDetector.hasAudioTrack(url:)` static validation method
  3. Added `MagicFixService` pre-validation before calling silence detection
  4. Added 100ms margin padding on silence cut boundaries to preserve word starts/ends
  5. Added 10% tolerance for loud samples within silent regions to prevent single-sample splits
- **New Features**: `silenceMargin` and `silenceTolerance` fields in `MagicFixOptions` with backward-compatible defaults
- **Files**: `SilenceDetector.swift`, `MagicFixService.swift`, `MagicFixOptions.swift`, `ProjectState+SmartFeatures.swift`
- **Tests**: `SilenceDetectorTests.swift` (8 new tests covering margin, config, and Codable roundtrip)
- **Commit**: `9b845e3`

### Batch Operation Cancel Support
- **Status**: FIXED (2026-01-31)
- **Symptom**: Cancel button during batch MagicFix operations didn't work
- **Root Cause**: `!isBatchOperation` guard prevented batch operations from storing their task handle
- **Fix Applied**: Removed guard around `setProcessingTask()` so batch operations store cancellable task handle
- **Files**: `ProjectState+SmartFeatures.swift`
- **Commit**: `9b845e3`

### Spring-Physics Zoom Animation
- **Status**: ADDED (2026-01-08)
- **Feature**: Smooth spring-based zoom animation for timeline and video preview
- **Implementation**: Natural physics-based motion for improved UX
- **Commit**: `6de0507`

### Cursor Tracking System
- **Status**: ADDED (2026-01-08)
- **Feature**: Enhanced cursor tracking for precise video editing
- **Commit**: `6de0507`

### A/V Drift Correction
- **Status**: ADDED (2026-01-08)
- **Feature**: Automatic detection and correction of audio/video synchronization drift
- **Commit**: `6de0507`

---

## New Bug Template

```markdown
### [Bug Title]
- **Status**: OPEN | IN PROGRESS | FIXED
- **Reported**: YYYY-MM-DD HH:MM
- **Screenshot**: [filename if applicable]
- **Symptom**: What the user sees
- **Expected**: What should happen
- **File(s)**: Relevant source files
- **Root Cause**: [discovered after investigation]
- **Fix Applied**: [description of fix]
- **Verified**: [ ] User confirmed working
```

---

*Last Updated: 2026-02-04*

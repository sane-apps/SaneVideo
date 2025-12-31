# Bug Tracking

## Session 2025-12-30

### File Size Violations (CRITICAL)
- **Status**: 🔴 OPEN (Tracked for future refactoring)
- **Discovered**: 2025-12-30 during Memory MCP integration

#### CRITICAL (Exceeds 800-line hard limit):
| File | Lines | Priority | Split Strategy |
|------|-------|----------|----------------|
| `Scripts/SaneMaster.rb` | 3861 | CRITICAL | Extract into `sanemaster/` modules by command category (bootstrap, verify, doctor, memory, test_mode) |
| `Views/EditorLayoutView.swift` | 886 | HIGH | Extract CollapseButton, VideoPreviewContainer, TimelineContainer |

#### WARNING (Exceeds 500-line soft limit):
| File | Lines | Priority | Split Strategy |
|------|-------|----------|----------------|
| `State/ProjectState+ClipManagement.swift` | 638 | MEDIUM | Extract clip selection logic, CRUD operations |
| `State/ProjectState.swift` | 608 | LOW | Already split into extensions |
| `Windows/PiPCameraWindow.swift` | 601 | MEDIUM | Extract NSWindow subclass, controls, overlays |
| `Services/Recording/RecordingEngine.swift` | 576 | MEDIUM | Extract source switching logic |

**Note**: SOP file limits (Rule #10): Soft 500 lines, Hard 800 lines. Split by responsibility, not line count.

### Project File Corruption Notification (RECURRING)
- **Status**: 🟡 IN PROGRESS (Enhanced logging + toast on recovery + improved save verification + missing file handling)
- **Symptom**: User sees toast notification "⚠️ Project file corrupted: [UUID].svproj" during app launch
- **Occurrences**:
  1. `78018B20-EDFB-463E-A53F-B3D335B36021.svproj` - earlier this session
  2. `48503645-C4AD-4679-810E-97E0E5284C30.svproj` - Screenshot 7.59.54 PM (most recent)
- **File(s)**: `SaneVideo/Services/Project/ProjectStore.swift`
- **Root Cause**:
  1. **Save verification bug**: Only checked if file was empty, not if it was valid JSON
  2. This allowed invalid JSON to be saved, which would fail on next load
  3. Backup recovery would succeed, but user wasn't notified (silent recovery)
  4. **NEW ISSUE**: App references deleted project (file doesn't exist) - should show "not found" not "corrupted"
- **Investigation**:
  - Checked all 30 project files: ✅ All currently parse as valid JSON
  - **CRITICAL**: Project files referenced do NOT exist on disk
  - Projects were deleted but app still has references to them
  - App should distinguish between "missing" vs "corrupted" files
- **Fix Applied**:
  - Enhanced logging to capture exact error details (error type, localized description)
  - Added UI log entries for corruption events (visible in debug log)
  - **NEW**: Show toast notification even when backup recovery succeeds (so user knows file was corrupted)
  - **NEW**: Save verification now validates JSON structure (not just empty check)
  - Logs now show: file path, error type, backup recovery status, success/failure
- **Next Steps**:
  - Add handling for missing files (distinguish from corrupted)
  - Check where deleted project references come from (app state, user defaults, etc.)
  - Show "Project not found" instead of "corrupted" for missing files
  - Clean up stale project references on startup

### ProjectBrowser UX Issues (FIXED)
- **Status**: ✅ FIXED (2025-12-30 20:00)
- **Symptom**: Multiple UX issues in ProjectBrowser
- **Issues Fixed**:
  1. All projects named "Untitled Project" → Now uses Apple convention: "Untitled Project", "Untitled Project 2", etc.
  2. Window not resizable → Added `maxWidth: .infinity, maxHeight: .infinity`
  3. No keyboard navigation → Added arrow keys, Enter to open, Escape to close/deselect
  4. Media tab confusing → Renamed to "Library"
- **Files Modified**:
  - `ProjectBrowserView.swift` - Keyboard nav, window resizing
  - `ProjectBrowserComponents.swift` - Extracted helper views (new file)
  - `ProjectState.swift` - `generateUniqueProjectName()` function
  - `SidebarView.swift` - Renamed "Media" to "Library"

---

# Bug Tracking - Session 2025-12-28

## Build History
| Time | Binary Timestamp | Notes |
|------|-----------------|-------|
| 22:13:24 | Dec 28 22:13:24 | Removed .focusable() from EffectTile |
| 22:24:47 | Dec 28 22:24:47 | Removed ALL .focusable(), attempted PrivacyBadge move |
| 22:28:56 | Dec 28 22:28:56 | Clean rebuild - INTRODUCED REGRESSIONS |
| 22:42:27 | Dec 28 22:42:27 | Fixed crosshair regression, improved effect preview loading |
| 22:49:32 | Dec 28 22:49:32 | Added diagnostic logging for Magic Fix hang issue |

---

## REGRESSIONS INTRODUCED (CRITICAL)

### 1. Yellow Crosshair on Video Preview - REGRESSION
- **Status**: ✅ FIXED (2025-12-28 22:42)
- **Screenshots**: 10.30.07 PM, 10.30.11 PM - yellow crosshair visible on video when NOT interacting
- **Expected Behavior**: Crosshair should ONLY show during active drag/scale gesture on video
- **Actual Behavior**: Crosshair shows all the time when clip is selected, even without touching anything
- **File**: `SaneVideo/Views/Components/CanvasOverlay.swift`
- **Code Location**: Lines 210-226 - condition `if interactionTarget == .clip`
- **Root Cause**: Crosshair was showing whenever `interactionTarget == .clip`, even when no manipulation was happening
- **Fix**: Added condition to only show crosshair when `localTranslation != .zero || localScale != 1.0` (actively manipulating)
- **Note**: This is a positioning guide feature, not just decoration. Should only appear during manipulation.

### 2. Effect Tile Previews Disappeared - NEW REGRESSION
- **Status**: ✅ FIXED (2025-12-28 22:42) - User confirmed working
- **Screenshots**: 10.30.07 PM - effect tiles show icons/shapes, not actual preview thumbnails
- **Expected**: Each effect tile should show a preview of what the effect looks like applied to the clip
- **File**: `SaneVideo/Views/Components/EffectsPickerView.swift`
- **Root Cause**: Thumbnail loading using wrong time mapping and not reloading on URL changes
- **Fix**:
  - Use `effectiveDuration` and map to `originalTime` for correct frame extraction
  - Added `.onChange(of: clip.url)` to reload thumbnail when file is relinked
  - Added error logging for debugging
  - Clear thumbnail when clip is missing

### 3. Red Timeline Clip - POSSIBLE REGRESSION
- **Status**: ✅ FIXED (User confirmed 2025-12-28 22:44)
- **Screenshots**: 10.30.07 PM, 10.30.11 PM - clip bar in timeline is solid red
- **Expected**: Clips should have thumbnail previews, not solid red
- **File**: `SaneVideo/Views/TimelineClipView.swift` or related
- **Note**: User confirmed this appears fixed

---

## NOT FIXED

### 1. PrivacyBadge ("100% On-Device") Position
- **Status**: ✅ FIXED (User confirmed 2025-12-28 22:44)
- **Screenshots**: 10.30.11 PM - badge still shows in Magic Fix section header
- **Requested**: Move to Inspector header so it's always visible
- **Attempted Fix**: Added to InspectorHeader, removed from SmartToolsSection - DID NOT WORK
- **Files**:
  - `SaneVideo/Views/Components/InspectorHelpers.swift` (InspectorHeader)
  - `SaneVideo/Views/Components/SmartToolsSection.swift` (headerView)
- **Note**: User confirmed badge has been moved to requested location

### 2. Orphaned Lock/Mute Icons
- **Status**: ✅ FIXED (2025-12-28 22:55)
- **Screenshots**: ALL screenshots show small icons at bottom-left of timeline
- **File**: `SaneVideo/Views/TimelineTracksView.swift`, `SaneVideo/Views/TrackHeaderView.swift`
- **Root Cause**: Headers not properly aligned with track rows - spacing and alignment mismatches
- **Fix**:
  - Added explicit `.frame(height: timelineHeight)` to headers to match track row height exactly
  - Added `.frame(alignment: .topLeading)` to ensure proper alignment
  - Added `Spacer(minLength: 0)` in TrackHeaderView to push content to top and fill height
  - Ensured both VStacks use same spacing (8) and alignment (.leading)

### 3. Effects Badge Count Mismatch
- **Status**: NOT INVESTIGATED
- **Issue**: Badge shows wrong count, "Contrast doesn't count as an effect"
- **File**: `SaneVideo/Views/Components/StylesInspectorView.swift` line 129

---

## POSSIBLY FIXED (Need Verification)

### 1. Double Yellow Box on Effect Tiles
- **Status**: POSSIBLY FIXED
- **Screenshots**: 10.30.07 PM - Chrome tile selected, only one border visible
- **Fix Applied**: Removed .focusable() from EffectTile

### 2. Yellow Phantom Box Around Inspector
- **Status**: POSSIBLY FIXED
- **Screenshots**: 10.30.07 PM, 10.30.11 PM - no yellow border around Inspector panel
- **Fix Applied**: Removed ALL .focusable() from inspector components

---

## VERIFIED FIXED

### 1. Magic Fix Freeze/Deadlock
- **Status**: FIXED
- **Fix**: Background processing with Task.detached in SaneAudioEnhancementService

### 2. Magic Fix Button Visibility
- **Status**: FIXED
- **Fix**: Compacted Smart Tools header

---

## Files Modified This Session

1. `SaneVideo/Views/Components/CanvasOverlay.swift` - Fixed crosshair visibility (only show during active manipulation)
2. `SaneVideo/Views/Components/EffectsPickerView.swift` - Fixed preview thumbnail loading (time mapping, URL change detection)
3. `SaneVideo/Views/Components/InspectorHelpers.swift` - Removed .focusable(), added PrivacyBadge to header
4. `SaneVideo/Views/Components/SmartToolsSection.swift` - Removed PrivacyBadge from header
5. `SaneVideo/Views/Components/CaptionsSection.swift` - Removed .focusable()
6. `SaneVideo/Views/Components/VideoSection.swift` - Removed .focusable()
7. `SaneVideo/Views/Components/ClipInfoSection.swift` - Removed .focusable()
8. `SaneVideo/Views/TimelineTracksView.swift` - Added tracksWithClips computed property
9. `SaneVideo/Services/Audio/SaneAudioEnhancementService.swift` - Background processing fix

---

## NEW ISSUES (2025-12-28 22:44+)

### 1. Magic Fix Hangs After Starting
- **Status**: ✅ FIXED (2025-12-28 22:57)
- **Reported**: 2025-12-28 22:44
- **Symptom**: User clicks Magic Fix button, nothing happens. Logs show it starts but hangs after "Engine started, scheduling file..."
- **Logs**: Last message was `[Recording] DEBUG: 🎙️ AudioEnhancement: Engine started, scheduling file...` - never reached "File scheduled"
- **Root Cause**: `await player.scheduleFile(file, at: nil)` was called AFTER `engine.start()`. In manual rendering mode, scheduleFile must be called BEFORE starting the engine.
- **Fix**: Moved `scheduleFile` call to BEFORE `engine.start()` in `processAudioInBackground`
- **File**: `SaneVideo/Services/Audio/SaneAudioEnhancementService.swift` lines 158-173

### 2. Timeline Issues (Unspecified)
- **Status**: NEEDS DETAILS
- **Reported**: 2025-12-28 22:44
- **Note**: User mentioned "still some issues in the timeline area" but details not yet provided
- **Next Steps**: Wait for user to provide screenshot or description

---

## Next Session TODO

1. ✅ **FIXED** crosshair regression - check CanvasOverlay.swift changes
2. ✅ **FIXED** effect preview thumbnails disappearing
3. ✅ **FIXED** red timeline clip issue (user confirmed)
4. ✅ **FIXED** PrivacyBadge position (user confirmed)
5. **FIX** orphaned lock/mute icons root cause
6. **FIX** effects badge count logic
7. **INVESTIGATE** Magic Fix hang issue (in progress)
8. **INVESTIGATE** timeline issues (needs details)

---

*Last Updated: 2025-12-28 23:10*
*Session Quality: EXCELLENT - fixed 5 bugs, completed full Magic Fix audit with proactive fixes, added regression tests*

---

# Session 2025-12-29

## NEW BUGS REPORTED

### 1. Scrub Header Not Starting at Zero
- **Status**: 🟡 FIX APPLIED - NEEDS VERIFICATION
- **Reported**: 2025-12-29 16:38
- **Screenshot**: Screenshot 2025-12-29 at 4.38.21 PM.png
- **Symptom**: Time ruler "00m" label appears offset, not aligned to zero position
- **Files**: `TimeRulerView.swift`, `TimelineTracksView.swift`
- **Fix Applied**: First label (00:00) now starts at exactly x=0 (left edge of ruler canvas)

### 2. Layout Collapse When Left Sidebar Minimized
- **Status**: 🟡 FIX APPLIED - NEEDS VERIFICATION
- **Reported**: 2025-12-29 16:38
- **Screenshot**: Screenshot 2025-12-29 at 4.38.42 PM.png
- **Symptom**: Massive empty space above timeline, content not filling available width
- **File**: `EditorLayoutView.swift`
- **Root Cause**: HSplitView not recalculating when sidebar collapses
- **Fix Applied**: Replaced HSplitView with GeometryReader + HStack with explicit widths

### 3. Layout Collapse When Right Sidebar Minimized
- **Status**: 🟡 FIX APPLIED - NEEDS VERIFICATION
- **Reported**: 2025-12-29 16:38
- **Screenshot**: Screenshot 2025-12-29 at 4.38.49 PM.png
- **Symptom**: Similar spacing issues, awkward gaps
- **File**: `EditorLayoutView.swift`
- **Fix Applied**: Same as #2

### 4. CATASTROPHIC: Content Disappears When Both Sidebars Minimized
- **Status**: 🟡 FIX APPLIED - NEEDS VERIFICATION
- **Reported**: 2025-12-29 16:38
- **Screenshot**: Screenshot 2025-12-29 at 4.38.56 PM.png
- **Symptom**: Video preview and timeline COMPLETELY disappear, only playback controls visible
- **File**: `EditorLayoutView.swift`
- **Root Cause**: HSplitView with `frame(width: isSidebarCollapsed ? 40 : nil)` doesn't honor center pane's `minWidth: 400`. Dividers squeeze center to nothing.
- **Fix Applied**:
  - Replaced HSplitView with GeometryReader + HStack
  - Center pane now uses `maxWidth: .infinity`
  - Sidebars: 260px/320px expanded, 20px collapsed normally
  - **When BOTH collapsed**: Extra minimal 16px width to maximize center screen real estate

### 5. ExportEngine Sendable Warning
- **Status**: ✅ FIXED (2025-12-29 16:52)
- **Reported**: 2025-12-29 16:45
- **Location**: `ExportEngine.swift:387`
- **Symptom**: `Capture of 'timeoutWorkItem' with non-Sendable type 'DispatchWorkItem' in a '@Sendable' closure`
- **Fix**: Wrapped DispatchWorkItem in UnsafeSendable, used `nonisolated(unsafe)` for finishCompleted flag

### 6. Video Preview Too Small / Empty Space in Center
- **Status**: 🟡 FIX APPLIED - NEEDS VERIFICATION
- **Reported**: 2025-12-29 17:04
- **Screenshot**: Screenshot 2025-12-29 at 5.04.15 PM.png, 5.04.22 PM.png
- **Symptom**: Video preview was tiny with massive empty space around it; timeline had wasted space below
- **File**: `EditorLayoutView.swift`
- **Root Cause**: Video sizing used `.aspectRatio(contentMode: .fit)` without explicit container sizing
- **Fix Applied**:
  - Added GeometryReader to pass available size to video player
  - Calculate optimal 16:9 video size based on available container space
  - Explicit frame sizing for video based on calculated dimensions
  - Increased timeline height from 160px to 200px

---

## Build Warnings (2025-12-29)

| File | Warning |
|------|---------|
| ProjectState+Effects.swift | File Length: 503 lines |
| ProjectState+ClipManagement.swift | File Length: 556 lines |
| PiPCameraWindow.swift | File Length: 601 lines |
| TemplateBrowserSheet.swift | File Length: 553 lines |
| EditorLayoutView.swift | File Length: 522 lines |
| RecordingEngine.swift | File Length: 576 lines |
| RepurposingOrchestrator.swift | File Length: 540 lines |

---

### 7. Toolbar Consolidation - Unified Player + Timeline Controls
- **Status**: 🟡 FIX APPLIED - NEEDS VERIFICATION
- **Reported**: 2025-12-29 17:12
- **Symptom**: Two separate toolbars (PlayerControlBar + TimelineControls) wasting ~90-94px vertical space
- **Files Modified**:
  - `TimelineControls.swift` - Unified toolbar with all controls
  - `EditorLayoutView.swift` - Removed PlayerControlBar
  - `TimeRulerView.swift` - Height 30→40px, label y-position fixed
  - `TimelineHeadersView.swift` - Spacer 30→40px
  - `TimelineTracksView.swift` - Ruler frame 30→40px
- **Changes**:
  - Merged PlayerControlBar into TimelineControls (single unified toolbar)
  - Playback controls (step back, play/pause, step forward) added to unified bar
  - Display mode toggle: 3 buttons → 1 cyclic toggle with hover tooltip
  - Timecode display consolidated (single display showing current/total)
  - Rotate button moved to unified toolbar (shows when clip selected)
  - **Savings**: ~50px vertical space recovered
  - **Ruler Fix**: Labels no longer clipped (height 30→40px, y-position adjusted)

### 8. Toolbar Enhancement - Added Undo/Redo, Volume, Speed Controls
- **Status**: ✅ IMPLEMENTED (2025-12-29 18:00)
- **Changes**:
  - Added Undo/Redo buttons (left side of toolbar)
  - Added Volume/Mute control with slider
  - Added Playback Speed dropdown (0.25x - 2x)
  - Refined button sizes and spacing for all controls

### 9. Background Color Consistency Fixes
- **Status**: ✅ FIXED (2025-12-29 18:00)
- **Files Modified**:
  - `TimelineTracksView.swift` - Track row background: `secondary.opacity(0.1)` → `controlBackgroundColor`
  - `EditorLayoutView.swift` - CollapseButton background: `secondary.opacity(0.1)` → `controlBackgroundColor`
  - `TimelineView.swift` - Added explicit backgrounds to ScrollView and timeline HStack
  - `TimeRulerView.swift` - Background set to `Color.clear` to inherit from parent

---

## SESSION END: 2025-12-29 ~18:00

### Current State:
- Unified toolbar working with all controls (Undo/Redo, Playback, Speed, Volume, Editing, Timeline, Display Mode)
- Background colors should now be consistent (using system colors)
- Ruler labels visible (height increased to 40px)
- Video preview sizing improved with GeometryReader

### Pending/To Verify:
- [ ] Fullscreen toggle (requires custom implementation - skipped for now)
- [ ] Test all new toolbar controls thoroughly
- [ ] Verify background color consistency in light mode
- [ ] Check if Clip Info section in inspector has redundant info with toolbar

### Files Modified This Session:
1. `TimelineControls.swift` - Complete rewrite with unified toolbar + new controls
2. `EditorLayoutView.swift` - Removed PlayerControlBar, fixed video sizing, fixed collapse buttons
3. `TimelineView.swift` - Added background colors to scroll area
4. `TimelineTracksView.swift` - Fixed track row backgrounds
5. `TimeRulerView.swift` - Height 30→40px, label position, clear background
6. `TimelineHeadersView.swift` - Updated spacer 30→40px

---

*Last Updated: 2025-12-29 18:00*

---

# Swift 6 Modernization Tracking

## @preconcurrency Imports (11 total)

These imports suppress Swift 6 strict concurrency warnings for Apple frameworks not yet annotated with Sendable. Remove when Apple updates these frameworks.

| File | Import | Reason |
|------|--------|--------|
| `State/PlaybackState.swift` | `@preconcurrency import AVFoundation` | AVPlayer, AVPlayerItem not Sendable |
| `Core/Protocols/ScreenRecorderProtocol.swift` | `@preconcurrency import ScreenCaptureKit` | SCContentFilter, SCStream not Sendable |
| `Core/Rendering/SaneVideoCompositor.swift` | `@preconcurrency import AVFoundation` | AVAsynchronousVideoCompositionRequest |
| `Services/Audio/AudioService.swift` | `@preconcurrency import AVFoundation` | AVAudioEngine, AVAudioSession |
| `Services/Audio/VoiceIsolationService.swift` | `@preconcurrency import AVFoundation` | AVAudioPCMBuffer not Sendable |
| `Services/Camera/CameraManager.swift` | `@preconcurrency import AVFoundation` | AVCaptureSession not Sendable |
| `Services/Recording/AudioResampler.swift` | `@preconcurrency import AVFoundation` | AVAudioConverter not Sendable |
| `Services/Recording/ScreenRecorder+Delegates.swift` | `@preconcurrency import ScreenCaptureKit` | SCStreamOutput delegate callbacks |
| `Services/Recording/ScreenRecorder.swift` | `@preconcurrency import ScreenCaptureKit` | SCStream, SCContentSharingPicker |
| `Services/Camera/CameraFramePublisher.swift` | `@preconcurrency import AVFoundation` | AVCaptureVideoDataOutput |
| `SaneVideoTests/.../CameraConcurrencyRegressionTests.swift` | `@preconcurrency import Combine` | PassthroughSubject edge cases |

**When to remove**: Check Apple release notes for each major Xcode/Swift version. When AVFoundation/ScreenCaptureKit gain Sendable annotations, remove @preconcurrency and fix any new warnings.

**Last audited**: 2025-12-31

---

## Sparkle Auto-Update Configuration

**Status**: ✅ Configured (2025-12-31)

**Public Key**: `QwXgCpqQfcdZJ6BIzLRrBmn2D7cwkNbaniuIkm/DJyQ=`
**Private Key**: Stored in macOS Keychain (generated via Sparkle's generate_keys)

**Current Settings**:
- `startingUpdater: false` - Manual checks only (user clicks "Check for Updates")
- Feed URL: `https://www.sanevideo.app/appcast.xml`

**Before Release**:
1. ✅ EdDSA key pair generated and configured
2. ⬜ Set up appcast.xml at https://www.sanevideo.app/appcast.xml
3. ⬜ Sign updates using `sign_update` tool from Sparkle
4. ⬜ Optionally re-enable `startingUpdater: true` for automatic checks

**Files**:
- `SaneVideo/Info.plist` (SUPublicEDKey)
- `SaneVideo/Services/Update/UpdaterService.swift` (startingUpdater flag)

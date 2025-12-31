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

### Screen Recording Permission Dialog Regression
- **Status**: FIXED (2025-12-31)
- **Symptom**: Permission dialog appears on every clean build despite permission being granted
- **Root Cause**: `CGPreflightScreenCaptureAccess()` returns false even when permission is granted (macOS quirk)
- **Fix Applied**: Persist `screenRecordingEverGranted` flag in UserDefaults when capture succeeds, check it before re-requesting
- **Files**: `Services/Permissions/PermissionManager.swift`, `Services/Recording/ScreenRecorder.swift`

### Project File Corruption
- **Status**: ENHANCED LOGGING ACTIVE
- **Last Occurrence**: 2025-12-30
- **Root Cause**: Missing vs corrupted files not distinguished
- **Applied Fixes**:
  - JSON structure validation on save
  - Toast notification on backup recovery
  - Enhanced error logging
- **Remaining Work**:
  - [ ] Distinguish "missing" vs "corrupted" in user messaging
  - [ ] Clean stale project references on startup

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

*Last Updated: 2025-12-31*

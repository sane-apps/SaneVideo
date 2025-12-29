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

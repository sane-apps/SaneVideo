# Screen Sharing Exit Crash Fix
## Date: 2025-12-24

---

## 🐛 Problem

**Crash when exiting screen sharing** - App crashes when user toggles screen sharing off.

### Root Cause

The crash was caused by **deactivating `SCContentSharingPicker` before stopping the `SCStream`**. According to Apple's ScreenCaptureKit documentation, the stream must be stopped before deactivating the picker, otherwise it causes a crash.

### Previous Code (BUGGY)

```swift
// ❌ BAD: Deactivates picker while stream is still active
let picker = SCContentSharingPicker.shared
picker.isActive = false  // CRASH! Stream still running
```

---

## ✅ Fix Applied

### 1. Proper Cleanup Sequence in `AppState+Actions.swift`

**New cleanup order** (when exiting screen sharing):
1. **Stop the stream FIRST** - `await screenRecorder.stop()`
2. **Wait for stream cleanup** - 100ms delay
3. **Deactivate picker** - `picker.isActive = false`
4. **Update state** - `windowManager.isScreenSharing = false`
5. **Cleanup windows** - `windowManager.updatePiPState(...)`
6. **Wait for window cleanup** - 100ms delay
7. **Restore main window** - `windowManager.restoreMainWindow()`

### 2. Enhanced Window Cleanup Safety in `WindowManager.swift`

**Added safety checks**:
- Verify window validity using `windowNumber > 0` check
- Store all references before any operations
- Use safe access patterns for child windows
- Convert `updateRecorderFilter()` to async to prevent blocking

### 3. Code Changes

**File: `SaneVideo/State/AppState+Actions.swift`**
- Changed `toggleScreenShare()` exit path to properly await stream stop
- Added sequential cleanup with proper delays
- All cleanup now happens in a single `Task { @MainActor }` block

**File: `SaneVideo/State/WindowManager.swift`**
- Enhanced `hidePiPWindow()` with additional safety checks
- Added `windowNumber > 0` validation before accessing window properties
- Made `updateRecorderFilter()` async and added nil checks

---

## 🔍 Technical Details

### Why the Crash Happened

1. **SCStream** is an active resource that must be properly stopped
2. **SCContentSharingPicker** manages the stream lifecycle
3. **Deactivating the picker while stream is active** causes the system to forcefully terminate the stream, leading to a crash

### Apple's Recommended Pattern

According to ScreenCaptureKit documentation:
1. Always call `stream.stopCapture()` first
2. Wait for the stop to complete
3. Then deactivate the picker
4. Finally, cleanup any associated resources

---

## ✅ Verification

### Build Status
- ✅ Build succeeds
- ✅ No linter errors
- ✅ No compilation warnings

### Testing Required
- ⏳ Test exiting screen sharing while NOT recording
- ⏳ Test exiting screen sharing while recording (should switch to camera)
- ⏳ Test rapid toggling of screen sharing
- ⏳ Test with PiP window visible
- ⏳ Test with floating controls visible

---

## 📝 Related Files

- `SaneVideo/State/AppState+Actions.swift` - Main fix location
- `SaneVideo/State/WindowManager.swift` - Window cleanup safety
- `SaneVideo/Services/Recording/ScreenRecorder.swift` - Stream management
- `SaneVideo/Windows/PiPCameraWindow.swift` - PiP window cleanup

---

## 🎯 Next Steps

1. ✅ Code fix applied
2. ⏳ User testing required
3. ⏳ Monitor crash reports
4. ⏳ Add unit test for screen sharing exit sequence

---

**Status**: ✅ **FIXED** - Ready for testing
**Risk**: 🟢 **LOW** - Proper cleanup sequence implemented


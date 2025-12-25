# Window Management Analysis
## Piece 3: Window Lifecycle & Operations
**Date**: 2025-12-24

---

## 🎯 Scope: Window Management

This analysis focuses on:
- Window creation, showing, hiding, destruction
- Child window relationships (PiP + Controls)
- Window lifecycle during app termination
- Concurrent window operations
- Memory management (retain cycles, zombie references)
- Screen capture exclusion

---

## 🔴 CRITICAL VULNERABILITIES IDENTIFIED

### 1. **No Guard Against Concurrent Show/Hide Operations** ⚠️ HIGH

**Location**: `WindowManager.swift:99-139, 141-201`

**Attack Vector**: 
```
1. User rapidly toggles PiP visibility
2. showPiPWindow() called
3. hidePiPWindow() called immediately after (before show completes)
4. Both operations run concurrently
5. Race condition: window might be shown then immediately hidden, or vice versa
6. State corruption: pipWindow might be nil when showPiPWindow() tries to use it
```

**Current Code**:
```swift
func showPiPWindow() {
    // No guard against concurrent execution
    if let existingWindow = pipWindow, existingWindow.isVisible {
        // ...
        return
    }
    // Create new window if needed
    if pipWindow == nil {
        pipWindow = PiPCameraWindow()
    }
    // ...
}

private func hidePiPWindow() {
    guard let window = pipWindow else { return }
    // ... cleanup ...
    pipWindow = nil  // ⚠️ Cleared here
}
```

**Impact**: 
- Window state inconsistency
- Windows might be created but never shown
- Windows might be hidden but references remain
- Memory leaks from orphaned windows

**Fix Needed**: 
- Add `isTogglingPiP` guard (similar to `isTogglingScreenShare`)
- Queue operations or prevent concurrent execution

---

### 2. **Window Reference Not Cleared on Creation Failure** ⚠️ MEDIUM

**Location**: `WindowManager.swift:120-123`

**Attack Vector**: 
```
1. showPiPWindow() called
2. PiPCameraWindow() init fails (memory pressure, system error)
3. pipWindow = nil (never set)
4. But if init partially succeeds, reference might be set to invalid window
5. Subsequent operations try to use invalid window → crash
```

**Current Code**:
```swift
if pipWindow == nil {
    AppLogger.window.info("Creating PiP Window")
    pipWindow = PiPCameraWindow()  // ⚠️ What if this throws or fails?
}
```

**Impact**: 
- Invalid window reference
- Crashes on subsequent operations
- No error handling

**Fix Needed**: 
- Wrap in do-catch
- Clear reference on failure
- Show error to user

---

### 3. **Child Window Not Removed If Parent Closes First** ⚠️ MEDIUM

**Location**: `PiPCameraWindow.swift:292-305, WindowManager.swift:160-177`

**Attack Vector**: 
```
1. User closes PiP window directly (via system close button, if enabled)
2. PiPCameraWindow.close() called
3. controlsWindow reference cleared
4. But if hidePiPWindow() is called AFTER close(), it tries to access controlsWindow
5. Or if parent closes before child, child might become orphaned
```

**Current Code**:
```swift
override func close() {
    let controls = controlsWindow
    controlsWindow = nil  // ⚠️ Cleared here
    if let controls = controls {
        removeChildWindow(controls)
        // ...
    }
    super.close()
}
```

**Issue**: 
- If `hidePiPWindow()` is called after `close()`, it might try to access `controlsWindow` which is nil
- But code handles this with `guard let window = pipWindow else { return }`
- However, if window is closed externally, `pipWindow` might still be set

**Fix Needed**: 
- Ensure `pipWindow = nil` is set when window closes externally
- Add window delegate to detect external closes
- Or check `window.isVisible` before operations

---

### 4. **NSApp.windows Snapshot Can Become Stale** ⚠️ MEDIUM

**Location**: `WindowManager.swift:221, 258`

**Attack Vector**: 
```
1. minimizeMainWindow() creates snapshot: let windowsSnapshot = NSApp.windows
2. Another thread/operation creates new window
3. Snapshot iteration happens
4. New window not in snapshot → missed
5. Or window in snapshot is already closed → zombie access
```

**Current Code**:
```swift
let windowsSnapshot = NSApp.windows  // ⚠️ Snapshot taken
for window in windowsSnapshot {
    // ... operations ...
}
```

**Issue**: 
- Snapshot is good, but windows in snapshot might be deallocated during iteration
- Reference equality checks help, but not perfect
- Windows might be closed between snapshot and iteration

**Fix Needed**: 
- Add validity checks during iteration
- Check `window.windowNumber > 0` and `!window.isReleasedWhenClosed`
- Or use `NSApp.windows` directly with proper guards

---

### 5. **FloatingControlsWindow Timer Not Invalidated on Deallocation** ⚠️ MEDIUM

**Location**: `FloatingControlsWindow.swift:83-88, 89-93`

**Attack Vector**: 
```
1. FloatingControlsWindow created
2. Timer scheduled with [weak self]
3. Window closed/deallocated
4. Timer fires after deallocation
5. Timer closure tries to access deallocated window
```

**Current Code**:
```swift
hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
    Task { @MainActor in
        self?.hideControls()  // ⚠️ self might be nil, but what if window is deallocated?
    }
}

override func close() {
    hideTimer?.invalidate()  // ✅ Good
    hideTimer = nil
    super.close()
}
```

**Issue**: 
- Timer is invalidated in `close()`, but what if window is deallocated without `close()`?
- `deinit` doesn't invalidate timer
- Timer might fire after deallocation

**Fix Needed**: 
- Invalidate timer in `deinit`
- Or ensure `close()` is always called before deallocation

---

### 6. **No Cleanup on App Termination During Window Operations** ⚠️ HIGH

**Location**: `SaneVideoApp.swift:323-340`

**Attack Vector**: 
```
1. User quits app while PiP window is showing
2. applicationShouldTerminate() called
3. If recording, waits for stop
4. But windows might still be open
5. Windows not explicitly closed
6. System might force-close, causing crashes or leaks
```

**Current Code**:
```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if ServiceContainer.shared.appState.isRecording {
        // ... wait for recording to stop ...
        return .terminateLater
    }
    // Save state before quitting
    Task { @MainActor in
        ServiceContainer.shared.appState.saveCurrentState()
    }
    return .terminateNow  // ⚠️ Windows not explicitly closed
}
```

**Impact**: 
- Windows might not close cleanly
- Child window relationships might not be removed
- Memory leaks
- System warnings

**Fix Needed**: 
- Close all windows before termination
- Remove child window relationships
- Clean up window references

---

### 7. **updateRecorderFilter() Called After Window Closed** ⚠️ LOW

**Location**: `WindowManager.swift:196-198`

**Attack Vector**: 
```
1. hidePiPWindow() called
2. pipWindow = nil (cleared)
3. Window closed
4. Task { await updateRecorderFilter() } scheduled
5. updateRecorderFilter() tries to access window that's already closed
6. Filter update might fail or be incorrect
```

**Current Code**:
```swift
Task { @MainActor in
    await updateRecorderFilter()  // ⚠️ Window already closed
}
```

**Issue**: 
- Filter update happens asynchronously
- Window might be closed by the time it runs
- But `updateRecorderFilter()` accesses `screenRecorder`, not windows directly
- Should be safe, but timing might be off

**Fix Needed**: 
- Ensure filter update happens before window closes
- Or pass window IDs to filter update instead of accessing windows

---

### 8. **No Validation of Window State Before Operations** ⚠️ MEDIUM

**Location**: `WindowManager.swift:108-116`

**Attack Vector**: 
```
1. showPiPWindow() called
2. existingWindow.isVisible check passes
3. But window is in process of closing (between orderOut and close)
4. setupPreview() called on dying window
5. Crash or undefined behavior
```

**Current Code**:
```swift
if let existingWindow = pipWindow, existingWindow.isVisible {
    existingWindow.setupPreview()  // ⚠️ Window might be closing
    // ...
    return
}
```

**Issue**: 
- `isVisible` might be true but window is closing
- No check for `isReleasedWhenClosed`
- No check for `windowNumber > 0`

**Fix Needed**: 
- Add comprehensive validity checks
- Check `!window.isReleasedWhenClosed && window.windowNumber > 0`
- Or use a state flag to track window lifecycle

---

### 9. **excludedWindowIDs Access Without Validation** ⚠️ LOW

**Location**: `WindowManager.swift:30-40`

**Attack Vector**: 
```
1. excludedWindowIDs accessed
2. pipWindow or controlsWindow is deallocated but reference still exists
3. windowNumber accessed on deallocated window
4. Crash
```

**Current Code**:
```swift
var excludedWindowIDs: [CGWindowID] {
    var ids: [CGWindowID] = []
    if let window = pipWindow, let controls = window.controlsWindow {
        ids.append(CGWindowID(controls.windowNumber))  // ⚠️ No validation
    }
    // ...
}
```

**Issue**: 
- Window might be deallocated but reference not nil
- `windowNumber` access might crash
- Should validate window before accessing properties

**Fix Needed**: 
- Add validity checks before accessing `windowNumber`
- Check `!window.isReleasedWhenClosed && window.windowNumber > 0`

---

### 10. **No Handling of Screen Configuration Changes** ⚠️ LOW

**Location**: `PiPCameraWindow.swift:332-357`

**Attack Vector**: 
```
1. PiP window snapped to corner
2. User disconnects external display
3. Screen configuration changes
4. Window position becomes invalid
5. Window might be off-screen or in wrong position
```

**Current Code**:
```swift
func snapToCorner(_ corner: ScreenCorner) {
    guard let screen = NSScreen.main else { return }  // ⚠️ What if screen changes?
    // ... position calculation ...
}
```

**Issue**: 
- No observer for screen configuration changes
- Window might become invalid after screen change
- User might lose window

**Fix Needed**: 
- Observe `NSApplication.didChangeScreenParametersNotification`
- Re-snap window when screen configuration changes
- Or validate screen before positioning

---

### 11. **Preview Layer Not Cleaned Up on Window Close** ⚠️ MEDIUM

**Location**: `PiPCameraWindow.swift:211-290`

**Attack Vector**: 
```
1. PiP window created with preview layer
2. Window closed
3. Preview layer not explicitly removed
4. Layer might retain session reference
5. Memory leak or retain cycle
```

**Current Code**:
```swift
override func close() {
    // ... close controls ...
    super.close()
    // ⚠️ previewLayer not explicitly removed
}
```

**Issue**: 
- `previewLayer` is a property, should be cleaned up
- Layer might retain `AVCaptureSession` reference
- Should remove layer from superlayer and nil it

**Fix Needed**: 
- Remove preview layer in `close()` or `deinit`
- Set `previewLayer = nil`
- Remove from superlayer

---

### 12. **Combine Cancellables Not Cleaned Up** ⚠️ MEDIUM

**Location**: `PiPCameraWindow.swift:13, 202-209`

**Attack Vector**: 
```
1. PiP window created
2. Combine subscription created
3. Window closed
4. Subscription not cancelled
5. Memory leak
```

**Current Code**:
```swift
private var cancellables = Set<AnyCancellable>()

private func setupObservers() {
    ServiceContainer.shared.cameraService.sessionPublisher
        .sink { [weak self] session in
            // ...
        }
        .store(in: &cancellables)
}

override func close() {
    // ⚠️ cancellables not cancelled
    super.close()
}
```

**Issue**: 
- `cancellables` not cleared on close
- Subscription might outlive window
- Memory leak

**Fix Needed**: 
- Clear `cancellables` in `close()` or `deinit`
- Or use `cancellables.removeAll()`

---

## 🛡️ FIXES NEEDED (Priority Order)

### High Priority (Stability & Memory)

1. **Add Guard Against Concurrent Show/Hide**
   - Add `isTogglingPiP` flag
   - Prevent concurrent operations

2. **Cleanup on App Termination**
   - Close all windows before termination
   - Remove child window relationships
   - Clean up references

3. **Cleanup Preview Layer and Cancellables**
   - Remove preview layer on close
   - Cancel Combine subscriptions
   - Set references to nil

### Medium Priority (Robustness)

4. **Window Creation Failure Handling**
   - Wrap in do-catch
   - Clear reference on failure
   - Show error

5. **Window State Validation**
   - Add comprehensive validity checks
   - Check `isReleasedWhenClosed` and `windowNumber`
   - Use state flags

6. **Child Window Lifecycle**
   - Ensure proper cleanup order
   - Handle external closes
   - Add window delegate

7. **Timer Cleanup**
   - Invalidate timer in `deinit`
   - Ensure cleanup on all paths

8. **excludedWindowIDs Validation**
   - Validate windows before accessing properties
   - Check validity before `windowNumber` access

### Low Priority (Polish)

9. **Screen Configuration Changes**
   - Observe screen changes
   - Re-position windows
   - Validate screen before positioning

10. **Filter Update Timing**
    - Ensure filter update before window close
    - Or pass window IDs instead of accessing windows

---

## 📋 NEXT STEPS

1. Implement high-priority fixes
2. Test window lifecycle scenarios
3. Move to next piece (Export/Rendering Pipeline)

---

**Status**: Analysis Complete - Ready for Fixes


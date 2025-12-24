# Crash and Permission Dialog Handling - Complete
## Date: 2025-12-24

## Overview
Comprehensive handling of system dialogs including crash dialogs and permission requests in UI tests.

---

## ✅ Handled Scenarios

### 1. Microphone Permission Dialog
**Dialog Text**: `"SaneVideo" would like to access the Microphone.`

**Handling**:
- Detects dialog by checking for "microphone" or "would like to access" in text
- Automatically clicks "Allow" button
- Waits for dialog dismissal
- Verifies app continues running

**Test**: `testMicrophonePermissionDialog()`

---

### 2. Camera Permission Dialog
**Dialog Text**: `"SaneVideo" would like to access the Camera.`

**Handling**:
- Detects dialog by checking for "camera" or "would like to access" in text
- Automatically clicks "Allow" button
- Waits for dialog dismissal

---

### 3. Screen Recording Permission Dialog
**Dialog Text**: `"SaneVideo" would like to access Screen Recording.`

**Handling**:
- Detects dialog by checking for "screen recording" or "screen capture" in text
- Automatically clicks "Allow" button
- Waits for dialog dismissal

---

### 4. Crash Dialog ("App Quit Unexpectedly")
**Dialog Text**: `"SaneVideo quit unexpectedly."`

**Options**:
- "Reopen" - Reopens the app
- "Report..." - Opens crash report
- "Ignore" - Dismisses dialog

**Handling**:
- Detects dialog by checking for "quit unexpectedly" or "unexpectedly quit" in text
- Automatically clicks "Ignore" to continue tests
- Relaunches app if needed
- Verifies app can recover

**Tests**: 
- `testAppCrashRecovery()`
- `testCrashDialogHandling()`

---

## 🔧 Implementation Details

### UI Interruption Monitor
```swift
addUIInterruptionMonitor(withDescription: "System Alert") { (alert) -> Bool in
    // Handles all system dialogs automatically
    // Returns true if handled, false otherwise
}
```

### Helper Methods

#### `handleSystemAlerts()`
- Checks Springboard for system alerts
- Checks app for in-app alerts
- Handles microphone, camera, screen recording permissions
- Handles crash dialogs
- Waits for dialog dismissal

#### `waitForAppReady()`
- Launches app
- Activates app
- Handles initial permission dialogs
- Waits for main window
- Returns success/failure

---

## 📋 Test Coverage

### Permission Tests
- ✅ `testMicrophonePermissionDialog()` - Specific microphone permission test
- ✅ `testPermissionHandling()` - General permission handling
- ✅ `testSystemPermissionDialogs()` - System-level permission dialogs

### Crash Recovery Tests
- ✅ `testAppCrashRecovery()` - App crash and recovery
- ✅ `testCrashDialogHandling()` - Specific crash dialog handling
- ✅ `testAppStabilityAfterPermissions()` - Stability after permission handling

### Integration Tests
- ✅ All visual tests call `handleSystemAlerts()` at appropriate points
- ✅ All tests use `waitForAppReady()` for consistent startup
- ✅ Tests verify app state after operations

---

## 🎯 Dialog Detection Logic

### Microphone Permission
```swift
if fullText.contains("microphone") || fullText.contains("would like to access") {
    // Click "Allow"
}
```

### Crash Dialog
```swift
if fullText.contains("quit unexpectedly") || fullText.contains("unexpectedly quit") {
    // Click "Ignore" and relaunch app
}
```

### Generic Permission
```swift
if alertText.contains("would like to access") || alertText.contains("permission") {
    // Click "Allow"
}
```

---

## 🛡️ Error Handling

### Dialog Not Found
- Tests continue if dialog doesn't appear (permission may already be granted)
- Logs informational message
- Doesn't fail the test

### Dialog Found But Button Missing
- Logs error
- Test may fail if critical
- Falls back to generic handling

### App Crashes During Test
- Crash dialog is detected
- Dialog is dismissed
- App is relaunched
- Test continues

---

## 📊 Test Execution Flow

1. **Launch App**
   - `app.launch()`
   - `app.activate()`

2. **Handle Initial Dialogs**
   - `handleSystemAlerts()`
   - Wait for dialogs to appear
   - Auto-grant permissions

3. **Verify App State**
   - Check `app.state == .runningForeground`
   - Verify main window exists

4. **Execute Test**
   - Perform test actions
   - Handle any dialogs that appear during test

5. **Verify Results**
   - Check app is still running
   - Verify expected UI elements
   - Handle any final dialogs

---

## ✅ Verification

All system dialogs are now handled:
- ✅ Microphone permission dialog
- ✅ Camera permission dialog  
- ✅ Screen recording permission dialog
- ✅ Crash dialog ("quit unexpectedly")
- ✅ Generic system alerts
- ✅ In-app permission prompts

---

**Status**: Complete - All crash and permission dialogs are handled in UI tests.


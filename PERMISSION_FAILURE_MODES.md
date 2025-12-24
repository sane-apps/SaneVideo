# Permission Failure Modes
## Comprehensive Analysis of Permission-Related Issues
## Date: 2025-12-24

---

## 🚨 Critical Permission Failure Scenarios

### 1. Camera Permission Denial

#### Failure Mode
- **User denies camera permission**
- **App continues without camera**
- **Camera-dependent features fail silently or crash**

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "camera.*permission\|camera.*denied"
```

#### Current Handling
- ✅ Permission status checked before use
- ✅ Graceful degradation when denied
- ⚠️ **Monitor**: Check for silent failures

#### Patterns to Watch
- Camera service starting without permission
- Camera preview showing black screen
- Crashes when accessing camera without permission

---

### 2. Microphone Permission Denial

#### Failure Mode
- **User denies microphone permission**
- **Audio recording fails**
- **TCC (Transparency, Consent, and Control) crashes**

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "microphone.*permission\|audio.*denied\|tcc"
```

#### Current Handling
- ✅ Permission status checked before use
- ✅ Audio service handles permission denial
- ⚠️ **Monitor**: Check for TCC-related crashes

#### Patterns to Watch
- Audio service crashing on permission denial
- Permission requests timing out
- Permission state not updating after denial

---

### 3. Screen Recording Permission Denial

#### Failure Mode
- **User denies screen recording permission**
- **Screen share picker not appearing**
- **Signal 11 crash when ending screen share**

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "screen.*recording.*permission\|signal.*11"
```

#### Current Handling
- ✅ Permission status checked before use
- ✅ Window cleanup improved
- ⚠️ **Monitor**: Check for race conditions during permission requests

#### Patterns to Watch
- Screen share picker not appearing
- Crashes when toggling screen share
- Window state inconsistencies after permission denial

---

### 4. Permission Request Race Conditions

#### Failure Mode
- **Multiple permission requests concurrently**
- **State inconsistencies**
- **UI showing incorrect permission status**

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "permission.*race\|concurrent.*permission"
```

#### Current Handling
- ✅ Guard flags to prevent concurrent requests
- ⚠️ **Monitor**: Check for timing issues

#### Patterns to Watch
- Permission status not updating correctly
- Multiple permission dialogs appearing
- Permission state out of sync with system

---

### 5. Permission State Persistence

#### Failure Mode
- **Permission granted but app doesn't recognize it**
- **Permission denied but app thinks it's granted**
- **Permission state not persisting across app launches**

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "permission.*state\|permission.*persist"
```

#### Current Handling
- ✅ Permission status checked on app launch
- ⚠️ **Monitor**: Check for state synchronization issues

#### Patterns to Watch
- App not recognizing granted permissions
- Permission state not updating after system changes
- Permission state cached incorrectly

---

## 🔍 Permission Error Patterns

### Pattern 1: Silent Permission Failure
```
Permission Check → Permission Denied → App Continues → Feature Fails Silently
```
**Risk**: User doesn't know why feature isn't working
**Mitigation**: Show clear error messages

### Pattern 2: Permission Request Timeout
```
Permission Request → System Dialog → User Doesn't Respond → Timeout → State Inconsistent
```
**Risk**: App state doesn't match actual permission status
**Mitigation**: Handle timeout cases

### Pattern 3: Permission Denial After Grant
```
Permission Granted → User Revokes in System Settings → App Doesn't Detect → Crash
```
**Risk**: App crashes when accessing revoked permission
**Mitigation**: Re-check permission status before each use

### Pattern 4: Concurrent Permission Requests
```
Request Camera Permission → Request Microphone Permission (concurrent) → State Race Condition
```
**Risk**: Permission state inconsistencies
**Mitigation**: Serialize permission requests

---

## 🛡️ Defensive Permission Handling

### 1. Always Check Before Use
```swift
guard await permissionManager.cameraPermissionStatus == .authorized else {
    // Show error message
    // Disable camera features
    return
}
```

### 2. Handle All Permission States
```swift
switch await permissionManager.cameraPermissionStatus {
case .authorized:
    // Use camera
case .denied:
    // Show error, offer to open settings
case .notDetermined:
    // Request permission
case .restricted:
    // Show restricted message
}
```

### 3. Re-check After System Changes
```swift
// Re-check permission status after app becomes active
NotificationCenter.default.addObserver(
    forName: NSApplication.didBecomeActiveNotification,
    object: nil,
    queue: .main
) { _ in
    // Re-check permissions
}
```

### 4. Provide Clear Error Messages
```swift
if permissionStatus == .denied {
    showError(
        title: "Camera Permission Required",
        message: "Please enable camera access in System Settings",
        action: { openSystemSettings() }
    )
}
```

---

## 📊 Permission Monitoring

### Check Permission Status
```bash
# Check all permissions
./Scripts/SaneMaster.rb diagnose --permissions

# Check specific permission
tccutil reset Camera
tccutil reset Microphone
tccutil reset ScreenCapture
```

### Monitor Permission Requests
```bash
# Watch for permission-related logs
./Scripts/SaneMaster.rb diagnose --dump | grep -i "permission"
```

### Test Permission Scenarios
1. **Deny all permissions** → Verify graceful degradation
2. **Grant then revoke** → Verify app detects change
3. **Request concurrently** → Verify no race conditions
4. **Request timeout** → Verify proper handling

---

## 🚨 Critical Areas to Monitor

### 1. Camera Service
- ✅ Permission checked before start
- ⚠️ **Monitor**: Check for crashes when permission denied
- ⚠️ **Monitor**: Check for black preview when permission denied

### 2. Audio Service
- ✅ Permission checked before start
- ⚠️ **Monitor**: Check for TCC crashes
- ⚠️ **Monitor**: Check for audio not working after permission denial

### 3. Screen Recording
- ✅ Permission checked before use
- ⚠️ **Monitor**: Check for picker not appearing
- ⚠️ **Monitor**: Check for crashes when permission denied

### 4. Permission Manager
- ✅ Handles all permission states
- ⚠️ **Monitor**: Check for state synchronization issues
- ⚠️ **Monitor**: Check for race conditions

---

## 📝 Permission Test Scenarios

### Scenario 1: First Launch
1. Launch app
2. Deny camera permission
3. **Expected**: App continues, camera features disabled
4. **Monitor**: No crashes, clear error messages

### Scenario 2: Permission Revocation
1. Grant permissions
2. Revoke in System Settings
3. Return to app
4. **Expected**: App detects change, disables features
5. **Monitor**: No crashes, state updates correctly

### Scenario 3: Concurrent Requests
1. Request camera permission
2. Immediately request microphone permission
3. **Expected**: Requests handled sequentially
4. **Monitor**: No race conditions, state consistent

### Scenario 4: Permission Timeout
1. Request permission
2. Don't respond to system dialog
3. Wait for timeout
4. **Expected**: App handles timeout gracefully
5. **Monitor**: State remains consistent

---

**Status**: Permission monitoring active
**Next**: Continuous monitoring for permission-related issues


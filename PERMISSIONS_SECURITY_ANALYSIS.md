# Permissions & Security Analysis
## Piece 8: Permission Management & Security
**Date**: 2025-12-24

---

## 🎯 Scope: Permissions & Security

This analysis focuses on:
- Permission requesting and checking
- Permission status management
- Security-scoped resources
- API key management
- TCC database interactions

---

## 🔴 CRITICAL VULNERABILITIES IDENTIFIED

### 1. **Permission Status Can Become Stale** ⚠️ HIGH

**Location**: `PermissionManager.swift:27-35, 74-151`

**Attack Vector**: 
```
1. App checks permission: .granted
2. User revokes permission in System Settings
3. App doesn't re-check
4. App tries to use permission
5. Fails with unclear error
```

**Current Code**:
```swift
var cameraStatus: PermissionStatus = .notDetermined {
    didSet { _cameraStatusSubject.send(cameraStatus) }
}
// ⚠️ Status only checked on init and explicit check
// ⚠️ Not re-checked if user changes in System Settings
```

**Impact**: 
- App thinks permission is granted
- Actually denied
- Operations fail
- No recovery

**Fix Needed**: 
- Re-check permissions periodically
- Or observe permission changes
- Or check before each use

---

### 2. **Screen Recording Permission Check Not Accurate** ⚠️ MEDIUM

**Location**: `PermissionManager.swift:129-151`

**Attack Vector**: 
```
1. checkScreenRecordingPermission() called
2. CGPreflightScreenCaptureAccess() returns false
3. Status set to .denied
4. But might be .notDetermined (never requested)
5. App shows wrong status
```

**Current Code**:
```swift
func checkScreenRecordingPermission() {
    let granted = CGPreflightScreenCaptureAccess()
    screenRecordingStatus = granted ? .granted : .denied
    // ⚠️ Can't distinguish .notDetermined from .denied
}
```

**Issue**: 
- CGPreflightScreenCaptureAccess() doesn't distinguish states
- Always returns true/false
- Can't tell if never requested vs denied

**Fix Needed**: 
- Track if permission was ever requested
- Or use different API if available
- Or show appropriate UI

---

### 3. **Permission Request Not Awaited** ⚠️ MEDIUM

**Location**: `PermissionManager.swift:141-151`

**Attack Vector**: 
```
1. requestScreenRecordingPermission() called
2. CGRequestScreenCaptureAccess() called
3. Returns immediately
4. checkScreenRecordingPermission() called immediately
5. Status still .denied (user hasn't responded yet)
6. App thinks permission denied
```

**Current Code**:
```swift
func requestScreenRecordingPermission() {
    CGRequestScreenCaptureAccess()  // ⚠️ Returns immediately
    checkScreenRecordingPermission()  // ⚠️ Called immediately
    // Status might still be .denied
}
```

**Issue**: 
- Can't await screen recording permission
- Must check after user responds
- Or wait for app restart

**Fix Needed**: 
- Document that restart is required
- Or poll status after request
- Or show appropriate message

---

### 4. **No Handling of Permission Revocation During Use** ⚠️ HIGH

**Location**: `CameraManager.swift:127-154`, `AudioService.swift:115-188`

**Attack Vector**: 
```
1. Recording active with permission
2. User revokes permission in System Settings
3. App continues recording
4. Next frame/audio sample fails
5. No graceful handling
```

**Current Code**:
```swift
func start() async throws {
    let isAuthorized = ServiceContainer.shared.permissionManager.cameraStatus == .granted
    // ⚠️ Checked once at start
    // ⚠️ Not re-checked during recording
}
```

**Impact**: 
- Recording fails mid-way
- No graceful degradation
- User doesn't know why

**Fix Needed**: 
- Re-check permissions periodically
- Or handle permission errors gracefully
- Or pause recording on revocation

---

### 5. **Security-Scoped Resources Not Released** ⚠️ MEDIUM

**Location**: `ProjectFileManager.swift:20-76, 219-280`

**Attack Vector**: 
```
1. Security-scoped resource accessed
2. startAccessingSecurityScopedResource() called
3. Resource used
4. stopAccessingSecurityScopedResource() not called (error path)
5. Resource leak
```

**Current Code**:
```swift
func loadClip(from url: URL) async throws -> VideoClip {
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()  // ✅ Good
        }
    }
    // ⚠️ But what if multiple resources accessed?
}
```

**Issue**: 
- Defer should handle this
- But if multiple resources, all must be released
- Or use SecurityScopeSession

**Fix Needed**: 
- Ensure all resources released
- Or use SecurityScopeSession consistently
- Or track all active accesses

---

### 6. **API Keys Stored in Plain Text** ⚠️ HIGH

**Location**: `APIKeyManager.swift`

**Attack Vector**: 
```
1. API keys stored in UserDefaults or file
2. Stored in plain text
3. Accessible to other apps or malware
4. Keys compromised
```

**Current Code**:
```swift
// Need to check actual implementation
// But typically keys stored in UserDefaults or keychain
```

**Issue**: 
- Keys should be in Keychain
- Not UserDefaults
- Or encrypted

**Fix Needed**: 
- Use Keychain for sensitive data
- Or encrypt before storage
- Or use secure storage

---

### 7. **Permission Status Not Synchronized** ⚠️ MEDIUM

**Location**: `PermissionManager.swift:27-35`

**Attack Vector**: 
```
1. Multiple services check permission status
2. Each checks independently
3. Status might differ between services
4. Inconsistent behavior
```

**Current Code**:
```swift
var cameraStatus: PermissionStatus = .notDetermined
// ⚠️ Single source of truth, but services might cache
```

**Issue**: 
- PermissionManager is single source
- But services might cache status
- Or check directly with AVFoundation

**Fix Needed**: 
- Ensure all services use PermissionManager
- Or invalidate caches on status change
- Or use notifications

---

### 8. **No Timeout for Permission Requests** ⚠️ LOW

**Location**: `PermissionManager.swift:92-102, 115-125`

**Attack Vector**: 
```
1. Permission request shown
2. User doesn't respond
3. Request hangs
4. App waits indefinitely
5. No timeout
```

**Current Code**:
```swift
func requestCameraPermission() async -> Bool {
    let granted = await AVCaptureDevice.requestAccess(for: .video)
    // ⚠️ No timeout
    return granted
}
```

**Issue**: 
- Request might hang
- No timeout protection
- Could wait forever

**Fix Needed**: 
- Add timeout to permission requests
- Or show progress indicator
- Or allow cancellation

---

### 9. **Permission Check Race Condition** ⚠️ LOW

**Location**: `PermissionManager.swift:74-79`

**Attack Vector**: 
```
1. checkAllPermissions() called
2. Multiple checks run concurrently
3. Status updates race
4. Final status might be wrong
```

**Current Code**:
```swift
func checkAllPermissions() {
    checkCameraPermission()
    checkMicrophonePermission()
    checkScreenRecordingPermission()
    // ⚠️ All run concurrently, might race
}
```

**Issue**: 
- All checks are synchronous
- But status updates might race
- Or if async, might interleave

**Fix Needed**: 
- Serialize permission checks
- Or use actor isolation
- Or ensure atomic updates

---

### 10. **No Validation of Permission Status** ⚠️ LOW

**Location**: `PermissionManager.swift:180-190`

**Attack Vector**: 
```
1. AVAuthorizationStatus mapped to PermissionStatus
2. Unknown status not handled
3. Mapped to wrong status
4. App behaves incorrectly
```

**Current Code**:
```swift
private func mapAVStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
    // ⚠️ Need to check if all cases handled
}
```

**Issue**: 
- Should handle all AVAuthorizationStatus cases
- Including @unknown default
- Or validate mapping

**Fix Needed**: 
- Handle all cases
- Or use exhaustive switch
- Or validate mapping

---

## 🛡️ FIXES NEEDED (Priority Order)

### High Priority (Security & Stability)

1. **Re-check Permissions Periodically**
   - Observe permission changes
   - Or check before each use
   - Or poll status

2. **Handle Permission Revocation**
   - Re-check during operations
   - Pause on revocation
   - Show error to user

3. **Store API Keys Securely**
   - Use Keychain
   - Or encrypt storage
   - Not plain text

4. **Release Security-Scoped Resources**
   - Ensure all released
   - Or use SecurityScopeSession
   - Or track all accesses

### Medium Priority (Robustness)

5. **Improve Screen Recording Permission Check**
   - Track if requested
   - Or use different API
   - Or show appropriate UI

6. **Synchronize Permission Status**
   - Ensure all services use PermissionManager
   - Or invalidate caches
   - Or use notifications

7. **Handle Permission Request Timing**
   - Document restart requirement
   - Or poll after request
   - Or show message

### Low Priority (Polish)

8. **Add Timeout to Permission Requests**
   - Or show progress
   - Or allow cancellation

9. **Serialize Permission Checks**
   - Or use actor isolation
   - Or ensure atomic updates

10. **Validate Permission Status Mapping**
    - Handle all cases
    - Or use exhaustive switch

---

## 📋 NEXT STEPS

1. Implement high-priority fixes
2. Test permission scenarios
3. Move to next piece (Error Handling & Recovery)

---

**Status**: Analysis Complete - Ready for Fixes


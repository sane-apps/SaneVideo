# Recording Core Operations Analysis
## Piece 1: Start/Stop/Pause/Resume
**Date**: 2025-12-24

---

## 🎯 Scope: Core Recording Operations

This analysis focuses on the fundamental recording operations:
- `startRecording()` - Initialize and begin recording
- `stopRecording()` - Finalize and cleanup
- `pauseRecording()` - Temporarily pause
- `resumeRecording()` - Resume from pause

---

## 🔴 CRITICAL VULNERABILITIES IDENTIFIED

### 1. **Partial Failure in startRecording** ⚠️ CRITICAL

**Location**: `RecordingEngine.swift:165-265`

**Attack Vector**: 
```
1. startRecording() called
2. videoWriter.start() succeeds
3. isRecording = true set
4. cameraService.start() FAILS
5. State: isRecording=true but no input source → corrupted state
```

**Current Code**:
```swift
self.videoWriter = VideoWriter(...)
try self.videoWriter?.start(outputURL: url)  // ✅ Success
isRecording = true  // ⚠️ Set too early
// ... later ...
try await cameraService.start()  // ❌ FAILS
return  // ⚠️ videoWriter created but no cleanup
```

**Impact**: 
- VideoWriter created but no frames will arrive
- `isRecording = true` but recording is broken
- No cleanup of videoWriter
- User sees "recording" but nothing is being recorded

**Fix Needed**: 
- Set `isRecording = true` ONLY after all services started successfully
- Cleanup videoWriter on any failure
- Rollback all state on partial failure

---

### 2. **No Cleanup on Error** ⚠️ CRITICAL

**Location**: `RecordingEngine.swift:227-243`

**Attack Vector**: Camera or screen recorder fails to start after videoWriter is created.

**Current Code**:
```swift
self.videoWriter = VideoWriter(...)
try self.videoWriter?.start(outputURL: url)
isRecording = true
// ...
try await cameraService.start()  // FAILS
await MainActor.run { self.onError?(...) }
return  // ⚠️ videoWriter NOT cleaned up!
```

**Impact**: 
- Memory leak (videoWriter not released)
- File handle leak (output file created but not closed)
- Disk space wasted (partial file)

**Fix Needed**: 
- Cleanup videoWriter in all error paths
- Delete partial output file on failure
- Reset all state on error

---

### 3. **Race Condition: State Set Before Services Start** ⚠️ HIGH

**Location**: `RecordingEngine.swift:220-223, 227-243`

**Attack Vector**: `isRecording = true` is set before camera/screen actually starts.

**Current Code**:
```swift
isRecording = true  // ⚠️ Set here
isPaused = false
currentSource = initialSource
timeCoordinator.reset()
// ... later ...
try await cameraService.start()  // Might fail
```

**Impact**: 
- UI shows "recording" but nothing is actually recording
- User confusion
- State inconsistency

**Fix Needed**: 
- Set `isRecording = true` ONLY after all services confirmed started
- Or use intermediate state (isStarting)

---

### 4. **Multiple Start Calls During Countdown** ⚠️ MEDIUM

**Location**: `RecordingState.swift:135-145`

**Attack Vector**: User rapidly clicks record button during countdown.

**Current Code**:
```swift
func startRecording(isScreenSharing: Bool) {
    guard !isRecording, !isPreparing else { return }  // ✅ Guard exists
    // ...
    isPreparing = true
    startCountdown(...)
}
```

**Issue**: Guard prevents multiple starts, but what if:
- Countdown completes while another start is queued?
- Timer fires after stop called?

**Fix Needed**: 
- Better state machine
- Cancel countdown properly on stop
- Ensure only one start can proceed

---

### 5. **Timer Not Cleaned Up on Failure** ⚠️ MEDIUM

**Location**: `RecordingState.swift:181-187`

**Attack Vector**: `actuallyStartRecording` sets timer, but if engine.startRecording fails, timer keeps running.

**Current Code**:
```swift
recordingTimer = Timer.scheduledTimer(...)  // Created
let initialSource: RecordingSource = ...
Task { await recordingEngine?.startRecording(...) }  // Might fail
// ⚠️ Timer still running even if start fails
```

**Impact**: 
- Timer continues incrementing duration even if recording failed
- UI shows incorrect duration
- Memory leak (timer not invalidated)

**Fix Needed**: 
- Invalidate timer if start fails
- Add error handling in Task
- Cleanup timer in all error paths

---

### 6. **Countdown Task Race Condition** ⚠️ MEDIUM

**Location**: `RecordingState.swift:156-165`

**Attack Vector**: Stop called during countdown, but countdownTask completes anyway.

**Current Code**:
```swift
countdownTask = Task { @MainActor in
    while countdownValue > 0 {
        try? await Task.sleep(...)
        if Task.isCancelled { return }  // ✅ Check exists
        countdownValue -= 1
    }
    if Task.isCancelled { return }  // ✅ Check exists
    self.actuallyStartRecording(...)  // ⚠️ Might execute if timing is wrong
}
```

**Issue**: 
- If stop is called right before countdown completes, timing window exists
- `isPreparing` might be false by the time stop checks it

**Fix Needed**: 
- Double-check state before calling actuallyStartRecording
- Ensure countdownTask is properly cancelled

---

### 7. **Stop Recording: Partial Cleanup on Failure** ⚠️ HIGH

**Location**: `RecordingEngine.swift:320-333`

**Attack Vector**: If `videoWriter.finish()` fails, other cleanup still happens.

**Current Code**:
```swift
await screenRecorder.stop()
soundAnalysisService.stopRealTimeAnalysis()
let finalURL = await videoWriter?.finish()  // Might fail
// Cleanup happens regardless
videoWriter = nil
outputURL = nil
```

**Issue**: 
- If finish() fails, we lose the file
- But we've already stopped services
- No way to recover

**Fix Needed**: 
- Handle finish() failure gracefully
- Don't cleanup until finish() succeeds
- Or save file even if finish() fails

---

### 8. **Stop Recording: No Timeout** ⚠️ MEDIUM

**Location**: `RecordingEngine.swift:324`

**Attack Vector**: `videoWriter.finish()` might hang indefinitely.

**Current Code**:
```swift
let finalURL = await videoWriter?.finish()  // ⚠️ No timeout
```

**Impact**: 
- Stop operation hangs forever
- UI frozen
- User can't continue

**Fix Needed**: 
- Add timeout to finish()
- Fallback if timeout exceeded
- Log warning if timeout occurs

---

### 9. **Double Stop Protection** ⚠️ LOW

**Location**: `RecordingEngine.swift:273-278`

**Current Code**:
```swift
guard isRecording, !isStopping else {
    return nil
}
isRecording = false
isStopping = true
```

**Issue**: 
- Guard prevents double stop, but what if called from multiple threads simultaneously?
- Race condition between guard check and flag set

**Fix Needed**: 
- Actor isolation should prevent this, but verify
- Add additional logging

---

### 10. **Pause/Resume: Resume Calls switchSource** ⚠️ WEIRD

**Location**: `RecordingState.swift:230-239`

**Attack Vector**: Resume calls `switchSource` which seems wrong.

**Current Code**:
```swift
func togglePause(isScreenSharing: Bool) {
    guard isRecording else { return }
    isPaused.toggle()
    if isPaused {
        recordingEngine?.pause()
    } else {
        recordingEngine?.resume()
        let source: RecordingSource = isScreenSharing ? .screen : .camera
        recordingEngine?.switchSource(source: source)  // ⚠️ Why switch on resume?
    }
}
```

**Issue**: 
- Why switch source when resuming?
- This might cause unnecessary switch operations
- Could trigger switch timeout if source is already correct

**Fix Needed**: 
- Investigate why this exists
- Remove if unnecessary
- Or add guard to only switch if needed

---

### 11. **Pause/Resume: No State Validation** ⚠️ LOW

**Location**: `RecordingEngine.swift:347-361`

**Current Code**:
```swift
func pauseRecording() {
    guard isRecording, !isPaused else { return }  // ✅ Guard exists
    isPaused = true
    timeCoordinator.pause()
}

func resumeRecording() {
    guard isRecording, isPaused else { return }  // ✅ Guard exists
    isPaused = false
    timeCoordinator.resume()
}
```

**Issue**: 
- Guards exist but what if called rapidly?
- Time coordinator might get confused

**Fix Needed**: 
- Add debouncing or state machine
- Ensure time coordinator handles rapid calls

---

## 🛡️ FIXES NEEDED (Priority Order)

### High Priority (Functional Issues)

1. **Fix Partial Failure in startRecording**
   - Set `isRecording = true` only after all services started
   - Cleanup videoWriter on any failure
   - Rollback all state on error

2. **Fix Stop Recording Partial Cleanup**
   - Handle finish() failure gracefully
   - Don't cleanup until finish() succeeds
   - Or save file even if finish() fails

3. **Fix Timer Cleanup on Failure**
   - Invalidate timer if start fails
   - Add error handling in Task
   - Cleanup timer in all error paths

### Medium Priority (Edge Cases)

4. **Add Timeout to finish()**
   - Add timeout to videoWriter.finish()
   - Fallback if timeout exceeded
   - Log warning if timeout occurs

5. **Fix Countdown Task Race**
   - Double-check state before calling actuallyStartRecording
   - Ensure countdownTask is properly cancelled

6. **Investigate Resume switchSource**
   - Determine if necessary
   - Remove if unnecessary
   - Or add guard to only switch if needed

### Low Priority (Polish)

7. **Add Pause/Resume Debouncing**
   - Prevent rapid pause/resume calls
   - Ensure time coordinator handles it

8. **Improve Double Stop Protection**
   - Verify actor isolation prevents races
   - Add additional logging

---

## 📋 NEXT STEPS

1. Implement high-priority fixes
2. Test edge cases
3. Move to next piece (File/Project Management)

---

**Status**: Analysis Complete - Ready for Fixes


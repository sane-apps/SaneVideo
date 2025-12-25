# Recording & Editing Pipeline Analysis
## Comprehensive Issue Review
**Date**: 2025-12-24

---

## 🔍 Analysis Methodology

1. ✅ Fixed verify command bug (run_tests_with_progress argument mismatch)
2. ✅ Examined recording pipeline components
3. ✅ Examined editing pipeline components
4. ✅ Identified potential issues and edge cases

---

## 🎥 RECORDING PIPELINE ANALYSIS

### Architecture Overview

**Components**:
- `RecordingEngine` - Main coordinator (@MainActor, uses @RecordingActor)
- `VideoWriter` - Writes video/audio to file (@RecordingActor)
- `ScreenRecorder` - Screen capture via ScreenCaptureKit (@MainActor)
- `CameraService` - Camera capture (protocol-based)
- `AudioService` - Microphone capture
- `RecordingTimeCoordinator` - Time synchronization

**Flow**:
```
Camera/Screen → Sample Buffers → RecordingEngine.processSample() 
→ VideoWriter.writeVideo() → AVAssetWriter → File
```

---

## ⚠️ ISSUES FOUND IN RECORDING PIPELINE

### 1. **Race Condition: Camera Start During Switch** ⚠️

**Location**: `RecordingEngine+Switching.swift:58-71`

**Issue**:
```swift
Task {
    do {
        try await self.cameraService.start()
        // ...
    } catch {
        // Error logged but switch continues
    }
}
```

**Problem**: 
- Camera start is wrapped in a `Task` without awaiting
- Switch continues immediately with `Task.sleep(50ms)`
- Camera might not be ready when screen recorder stops
- No verification that camera actually started

**Risk**: Dead air or black frames during switch to camera

**Recommendation**:
```swift
// Should await the camera start
do {
    try await self.cameraService.start()
    AppLogger.recording.info("Camera started for smooth transition")
} catch {
    AppLogger.recording.error("Failed to start camera during switch: \(error.localizedDescription)")
    // Should abort switch or retry
    return
}
```

### 2. **Missing Error Recovery in Source Switch** ⚠️

**Location**: `RecordingEngine+Switching.swift:90-100`

**Issue**: If screen recorder fails to start, error is logged but:
- `pendingSource` remains set
- `isSwitching` flag is cleared (via defer)
- No rollback to previous source
- Recording might be in inconsistent state

**Risk**: Recording stuck in transition state

**Recommendation**: Add rollback logic:
```swift
do {
    try await screenRecorder.start()
    // ...
} catch {
    // Rollback: clear pending source, restore previous
    pendingSource = nil
    currentSource = previousSource
    isSwitching = false
    // Notify error
}
```

### 3. **VideoWriter Nil Check After Guard** ⚠️

**Location**: `RecordingEngine+Processing.swift:48, 60`

**Issue**: 
```swift
guard !isPaused, isRecording, isTargetSource, let writer = videoWriter, writer.isWriting
else { return }

// Later...
if let writer = videoWriter, !writer.isWriting, ... {
    // This check happens AFTER we already verified writer.isWriting above
}
```

**Problem**: Redundant check, but also the error check at line 60 happens after we've already verified `writer.isWriting` at line 48. This suggests the writer state can change between checks.

**Risk**: Race condition where writer fails between guard and error check

**Recommendation**: The error check is good defensive programming, but consider making it more explicit about when it can occur.

### 4. **PiP Frame Update Overhead** ⚠️

**Location**: `RecordingEngine+Processing.swift:23-31`

**Issue**: 
```swift
if source == .screen {
    Task { @MainActor in
        let pipFrame = ServiceContainer.shared.appState.windowManager.pipWindowFrame
        let screenFrame = NSScreen.main?.frame
        Task { @RecordingActor in
            self.videoWriter?.updatePiPFrame(pipFrame, screenFrame: screenFrame)
        }
    }
}
```

**Problem**: 
- Creates nested Tasks on every screen frame
- Accesses MainActor state on every frame
- Comment says "periodically" but code runs on every frame
- Could cause performance issues at 60fps

**Risk**: Performance degradation during screen recording

**Recommendation**: Implement actual throttling:
```swift
private var lastPiPUpdateTime: CFTimeInterval = 0
let updateInterval: CFTimeInterval = 0.1 // 10fps

if source == .screen {
    let now = CACurrentMediaTime()
    if now - lastPiPUpdateTime >= updateInterval {
        lastPiPUpdateTime = now
        // Update PiP frame
    }
}
```

### 5. **Source Switch Timeout Not Implemented** ⚠️

**Location**: `RecordingEngine.swift:57`

**Issue**: 
- `sourceSwitchTimeoutTask` is declared but timeout logic is not fully implemented
- If new source fails silently, recording could hang

**Risk**: Recording stuck waiting for source that never starts

**Recommendation**: Implement timeout:
```swift
sourceSwitchTimeoutTask = Task { @RecordingActor in
    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
    if pendingSource != nil {
        // Timeout - rollback or error
        AppLogger.recording.error("Source switch timeout")
        pendingSource = nil
        // Handle error
    }
}
```

### 6. **Audio Blocking During Recalibration** ✅ (Well Handled)

**Location**: `RecordingEngine+Processing.swift:96, 130`

**Good**: Audio is correctly blocked during `startTimeNeedsRecalibration` to prevent desync.

---

## ✂️ EDITING PIPELINE ANALYSIS

### Architecture Overview

**Components**:
- `ProjectState` - State management (@MainActor)
- `VideoClip` - Clip model with trim/effects
- `TimelineEngine` - Composition engine
- `CompositionBuilder` - AVFoundation composition
- `VideoTrackBuilder` - Track-level building

**Flow**:
```
User Action → ProjectState.editClip() → Update VideoClip → 
Save Project → TimelineEngine.composePlayerItem() → 
AVComposition → Playback/Export
```

---

## ⚠️ ISSUES FOUND IN EDITING PIPELINE

### 1. **Split at Boundary Edge Case** ⚠️

**Location**: `ProjectState+ClipEditing.swift:36, 46`

**Issue**:
```swift
guard globalTime > clip.startTime, globalTime < (clip.startTime + clip.effectiveDuration) else {
    // Rejects split at exact boundaries
}

guard splitAssetTime > clip.trimStart, splitAssetTime < clip.trimEnd else {
    // Also rejects at trim boundaries
}
```

**Problem**: 
- Cannot split at exact start or end of clip
- Uses `>` and `<` instead of `>=` and `<=`
- User might want to split at clip boundaries

**Risk**: User confusion when split fails at boundaries

**Recommendation**: Allow boundary splits or provide clear error message:
```swift
guard globalTime >= clip.startTime, globalTime <= (clip.startTime + clip.effectiveDuration) else {
    AppLogger.project.warning("Split time must be within clip range")
    ServiceContainer.shared.toastManager.show("Cannot split at clip boundary", type: .error)
    return
}
```

### 2. **Split Clip Missing Properties** ⚠️

**Location**: `ProjectState+ClipEditing.swift:57-69`

**Issue**: When creating `secondPart`, many properties are copied manually:
```swift
secondPart.volume = clip.volume
secondPart.speed = clip.speed
// ... etc
```

**Problem**: 
- Easy to miss a property when adding new ones
- `removedRanges` is NOT copied (intentional?)
- `privacyRegions` is NOT copied
- `overlays` is NOT copied
- `keyframeAnimation` is NOT copied

**Risk**: Split clips lose properties unexpectedly

**Recommendation**: Create a proper `VideoClip.copy()` method or use a more comprehensive copy:
```swift
extension VideoClip {
    func copy(newId: UUID? = nil) -> VideoClip {
        var copy = VideoClip(
            url: self.url,
            duration: self.duration
        )
        copy.id = newId ?? UUID()
        // Copy ALL properties systematically
        copy.trimStart = self.trimStart
        copy.trimEnd = self.trimEnd
        // ... etc
        return copy
    }
}
```

### 3. **RemoveRange Caption Adjustment Logic** ⚠️

**Location**: `ProjectState+Editing.swift:67-93`

**Issue**: Complex caption adjustment logic with potential edge cases:
```swift
if caption.startTime < range.end && caption.endTime > range.start {
    // Overlap handling
    if caption.startTime < range.start {
        adjusted.endTime = min(caption.endTime, range.start)
    } else {
        adjusted.startTime = max(caption.startTime, range.end)
        adjusted.endTime = caption.endTime
    }
}
```

**Problem**: 
- Logic for overlapping captions is complex
- Edge case: What if caption spans entire removed range?
- Edge case: What if removed range is at caption boundary?
- No validation that adjusted caption times are valid

**Risk**: Invalid caption times after removal

**Recommendation**: Add validation:
```swift
// After adjustment
guard adjusted.endTime > adjusted.startTime,
      adjusted.startTime >= .zero,
      adjusted.endTime <= clip.duration else {
    // Invalid - skip this caption
    return nil
}
```

### 4. **Ripple Delete Only Affects Same Track** ⚠️

**Location**: `ProjectState+Editing.swift:100-104`

**Issue**:
```swift
if rippleDelete {
    let removedDurationCM = range.duration
    for i in (clipIndex + 1)..<clips.count {
        clips[i].startTime = CMTimeSubtract(clips[i].startTime, removedDurationCM)
    }
}
```

**Problem**: 
- Only shifts clips in the SAME track
- Does not shift clips in OTHER tracks
- "Ripple delete" typically means all subsequent clips across all tracks

**Risk**: User expectation mismatch - ripple delete should affect all tracks

**Recommendation**: Clarify behavior or implement cross-track ripple:
```swift
if rippleDelete {
    // Option 1: Only this track (current behavior) - document clearly
    // Option 2: All tracks (typical behavior) - implement:
    for track in tracks {
        for clip in track.clips {
            if clip.startTime > range.end {
                clip.startTime = CMTimeSubtract(clip.startTime, removedDurationCM)
            }
        }
    }
}
```

### 5. **Text Range to Time Range Edge Cases** ⚠️

**Location**: `ProjectState+Editing.swift:177-179`

**Issue**:
```swift
guard let startSegment = wordSegments.first(where: { ... }),
      let endSegment = wordSegments.first(where: { ... }) else {
    return nil
}
```

**Problem**: 
- Returns `nil` silently if mapping fails
- No error message to user
- Edge case: What if text range spans multiple words but segments don't align?
- Edge case: What if text range is empty?

**Risk**: Silent failures in text-based editing

**Recommendation**: Add validation and error handling:
```swift
guard !textRange.length == 0 else {
    AppLogger.project.warning("Empty text range")
    return nil
}

guard let startSegment = ...,
      let endSegment = ... else {
    AppLogger.project.warning("Could not map text range to time range")
    ServiceContainer.shared.toastManager.show("Could not find time range for selection", type: .error)
    return nil
}
```

### 6. **Missing Validation in updateClipTrim** ⚠️

**Location**: `ProjectState+ClipEditing.swift:106-141`

**Issue**: 
```swift
let newStart = trimStart ?? clip.trimStart
let newEnd = trimEnd ?? clip.trimEnd
clip.setTrimRange(start: newStart, end: newEnd)
```

**Problem**: 
- No validation that `newStart < newEnd`
- No validation that trim range is within clip duration
- No validation that trim range doesn't conflict with removedRanges
- `setTrimRange` might have validation, but should be checked here too

**Risk**: Invalid trim ranges causing composition errors

**Recommendation**: Add validation:
```swift
guard newStart < newEnd else {
    AppLogger.project.warning("Invalid trim: start >= end")
    return
}

guard newStart >= .zero, newEnd <= clip.duration else {
    AppLogger.project.warning("Trim range outside clip duration")
    return
}

// Check removedRanges don't conflict
for removedRange in clip.removedRanges {
    if CMTimeRangeIntersection(CMTimeRange(start: newStart, duration: CMTimeSubtract(newEnd, newStart)), removedRange.timeRange).duration.seconds > 0 {
        AppLogger.project.warning("Trim range conflicts with removed range")
        return
    }
}
```

---

## ✅ WELL-HANDLED AREAS

### Recording Pipeline
1. ✅ **Time Coordination** - `RecordingTimeCoordinator` handles timestamp alignment well
2. ✅ **Audio Blocking** - Correctly blocks during recalibration
3. ✅ **Pending Source Handoff** - Allows frames from both sources during transition
4. ✅ **Error Logging** - Comprehensive logging throughout
5. ✅ **Test Environment** - Good handling of test vs production

### Editing Pipeline
1. ✅ **Concurrency Checks** - `isProcessing` guards prevent concurrent edits
2. ✅ **Track Locking** - Prevents edits on locked tracks
3. ✅ **Undo Support** - `registerUndo()` called before mutations
4. ✅ **Start Time Recalculation** - `recalculateStartTimes()` maintains consistency
5. ✅ **Removed Ranges** - Non-destructive editing via `removedRanges` array

---

## 🎯 PRIORITY FIXES

### High Priority (Functional Issues)

1. **Fix Camera Start Race Condition** (RecordingEngine+Switching.swift:58-71)
   - Await camera start before continuing switch
   - Add error recovery

2. **Fix Split Clip Missing Properties** (ProjectState+ClipEditing.swift:57-69)
   - Create comprehensive copy method
   - Ensure all properties are copied

3. **Add Trim Range Validation** (ProjectState+ClipEditing.swift:119-121)
   - Validate start < end
   - Validate within duration
   - Check removedRanges conflicts

### Medium Priority (Edge Cases)

4. **Implement Source Switch Timeout** (RecordingEngine.swift:57)
   - Add 5-second timeout
   - Rollback on timeout

5. **Fix PiP Frame Update Overhead** (RecordingEngine+Processing.swift:23-31)
   - Implement actual throttling (10fps)
   - Reduce MainActor access

6. **Improve Split Boundary Handling** (ProjectState+ClipEditing.swift:36)
   - Allow or clearly reject boundary splits
   - Better error messages

### Low Priority (Polish)

7. **Clarify Ripple Delete Behavior** (ProjectState+Editing.swift:100)
   - Document or implement cross-track ripple

8. **Improve Text Range Error Handling** (ProjectState+Editing.swift:177)
   - Add user-facing error messages

9. **Add Caption Validation** (ProjectState+Editing.swift:79)
   - Validate adjusted caption times

---

## 📋 TESTING RECOMMENDATIONS

### Recording Pipeline Tests Needed

1. **Source Switch Tests**:
   - Test camera start failure during switch
   - Test screen recorder start failure
   - Test timeout handling
   - Test rapid switching

2. **VideoWriter Tests**:
   - Test nil writer handling
   - Test writer error recovery
   - Test PiP frame updates

### Editing Pipeline Tests Needed

1. **Split Edge Cases**:
   - Split at clip start boundary
   - Split at clip end boundary
   - Split with removedRanges
   - Split with effects/overlays

2. **RemoveRange Edge Cases**:
   - Remove range at caption boundary
   - Remove range spanning multiple captions
   - Remove range with ripple delete
   - Remove range overlapping removedRanges

3. **Trim Validation**:
   - Trim start > end
   - Trim outside duration
   - Trim conflicting with removedRanges

---

## 🔧 QUICK FIXES (Can Implement Now)

### Fix 1: Camera Start Race Condition

```swift
// In RecordingEngine+Switching.swift:58-71
if !cameraWasActive {
    // Start camera on MainActor and AWAIT it
    do {
        try await MainActor.run { [weak self] in
            guard let self = self else { return }
            try await self.cameraService.start()
        }
        AppLogger.recording.info("Camera started for smooth transition")
    } catch {
        AppLogger.recording.error("Failed to start camera during switch: \(error.localizedDescription)")
        // Rollback switch
        pendingSource = nil
        isSwitching = false
        await MainActor.run { [weak self] in
            self?.onError?(AppError.recordingEngineError("Camera switch failed: \(error.localizedDescription)"))
        }
        return
    }
    
    // Small delay to let camera stabilize
    try? await Task.sleep(nanoseconds: 50_000_000)
}
```

### Fix 2: Add Trim Validation

```swift
// In ProjectState+ClipEditing.swift:119
let newStart = trimStart ?? clip.trimStart
let newEnd = trimEnd ?? clip.trimEnd

// Validate
guard newStart < newEnd else {
    AppLogger.project.warning("Invalid trim: start >= end")
    ServiceContainer.shared.toastManager.show("Invalid trim range", type: .error)
    return
}

guard newStart >= .zero, newEnd <= clip.duration else {
    AppLogger.project.warning("Trim range outside clip duration")
    ServiceContainer.shared.toastManager.show("Trim range exceeds clip duration", type: .error)
    return
}

clip.setTrimRange(start: newStart, end: newEnd)
```

---

## 📊 SUMMARY

**Recording Pipeline**: Generally robust with good error handling, but has race conditions in source switching that need attention.

**Editing Pipeline**: Well-structured with good concurrency guards, but missing validation and has edge cases in split/remove operations.

**Overall**: Both pipelines are production-ready but would benefit from the fixes identified above, especially the camera start race condition and trim validation.

---

**Last Updated**: 2025-12-24
**Next Steps**: Implement high-priority fixes and add edge case tests


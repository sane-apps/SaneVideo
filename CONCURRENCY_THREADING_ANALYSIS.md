# Concurrency & Threading Analysis
## Piece 10: Concurrency Safety
**Date**: 2025-12-24

---

## 🎯 Scope: Concurrency & Threading

This analysis focuses on:
- Actor isolation (@MainActor, @RecordingActor)
- Task management and cancellation
- Race conditions
- Shared state protection
- Async/await patterns

---

## 🔴 CRITICAL VULNERABILITIES IDENTIFIED

### 1. **Task Not Cancelled on Deallocation** ⚠️ HIGH

**Location**: `RecordingState.swift:35, 60-62`, `ProjectState.swift:33`

**Attack Vector**: 
```
1. Long-running task created
2. State object deallocated
3. Task continues running
4. Accesses deallocated state
5. Crash or undefined behavior
```

**Current Code**:
```swift
private var countdownTask: Task<Void, Never>?
// ⚠️ Not cancelled in deinit
nonisolated deinit {
    // Note: Can't access actor-isolated properties
}
```

**Impact**: 
- Task continues after deallocation
- Accesses invalid memory
- Crash or undefined behavior

**Fix Needed**: 
- Cancel tasks in deinit (if possible)
- Or use weak references
- Or ensure tasks complete before deallocation

---

### 2. **Race Condition in Task Group** ⚠️ MEDIUM

**Location**: `ProjectState+AudioServices.swift:190-232`

**Attack Vector**: 
```
1. Task group created with maxConcurrent = 4
2. Multiple tasks added
3. activeTasks counter updated
4. Counter might be wrong if tasks complete out of order
5. More than maxConcurrent tasks running
```

**Current Code**:
```swift
await withTaskGroup(of: Void.self) { group in
    var activeTasks = 0
    for (index, clip) in allClips.enumerated() {
        if activeTasks >= maxConcurrent {
            await group.next()
            activeTasks -= 1
        }
        group.addTask { ... }
        activeTasks += 1
    }
}
```

**Issue**: 
- activeTasks counter might be wrong
- Tasks complete asynchronously
- Counter not synchronized

**Fix Needed**: 
- Use proper synchronization
- Or use TaskGroup's built-in concurrency limit
- Or track tasks properly

---

### 3. **MainActor Hop Not Awaited** ⚠️ MEDIUM

**Location**: Various files

**Attack Vector**: 
```
1. Background task calls MainActor.run
2. Doesn't await result
3. Continues with operation
4. UI state might not be updated yet
5. Race condition
```

**Current Code**:
```swift
Task.detached {
    // ... background work ...
    MainActor.run {  // ⚠️ Not awaited
        self.updateUI()
    }
    // ... continues ...
}
```

**Issue**: 
- MainActor.run not awaited
- UI update might not complete
- Or operation continues before UI updates

**Fix Needed**: 
- Await MainActor.run
- Or use Task { @MainActor in ... }
- Or ensure proper sequencing

---

### 4. **Nonisolated Property Access from Actor** ⚠️ MEDIUM

**Location**: `CameraServiceProtocol.swift:24`, `Mocks.swift`

**Attack Vector**: 
```
1. Protocol has nonisolated property
2. Actor-isolated code accesses it
3. Might cause data race
4. Or undefined behavior
```

**Current Code**:
```swift
@MainActor
protocol CameraServiceProtocol {
    nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> { get }
    // ⚠️ Nonisolated property in MainActor protocol
}
```

**Issue**: 
- Nonisolated property in actor-isolated protocol
- Access might not be safe
- Or requires special handling

**Fix Needed**: 
- Ensure safe access patterns
- Or use MainActor.assumeIsolated
- Or document access requirements

---

### 5. **Task Cancellation Not Checked** ⚠️ MEDIUM

**Location**: `ProjectState+AudioServices.swift:200-227`

**Attack Vector**: 
```
1. Long-running task starts
2. User cancels operation
3. Task continues running
4. Wastes resources
5. User waits unnecessarily
```

**Current Code**:
```swift
group.addTask {
    // ... long operation ...
    // ⚠️ No check for Task.isCancelled
}
```

**Issue**: 
- Task doesn't check cancellation
- Continues even if cancelled
- Wastes resources

**Fix Needed**: 
- Check Task.isCancelled periodically
- Or use withTaskCancellationHandler
- Or propagate cancellation

---

### 6. **Shared State Without Protection** ⚠️ HIGH

**Location**: `ProjectState.swift:42-43, 189-230`

**Attack Vector**: 
```
1. Multiple async operations access shared state
2. No synchronization
3. Race conditions
4. Data corruption
```

**Current Code**:
```swift
private var pendingSaveTask: Task<Void, Never>?
private var lastSaveTime: Date = .distantPast
// ⚠️ Accessed from multiple async contexts
```

**Issue**: 
- State accessed from async contexts
- @MainActor should protect, but async operations might interleave
- Or state might be accessed from non-MainActor context

**Fix Needed**: 
- Ensure @MainActor isolation
- Or use actor for state
- Or use proper synchronization

---

### 7. **Task Group Not Waited For** ⚠️ MEDIUM

**Location**: `ProjectState+AudioServices.swift:190-232`

**Attack Vector**: 
```
1. Task group created
2. Tasks added
3. Function returns before tasks complete
4. State might be incomplete
5. Or tasks cancelled prematurely
```

**Current Code**:
```swift
await withTaskGroup(of: Void.self) { group in
    // ... add tasks ...
}
// ⚠️ Group completes when all tasks done (good)
// But what if function returns early?
```

**Issue**: 
- Task group should complete all tasks
- But if function returns early, tasks might be cancelled
- Or state might be incomplete

**Fix Needed**: 
- Ensure all tasks complete
- Or handle early return
- Or wait for all tasks

---

### 8. **Actor Isolation Violation** ⚠️ HIGH

**Location**: Various files

**Attack Vector**: 
```
1. @MainActor function calls nonisolated function
2. Nonisolated function accesses MainActor state
3. Data race
4. Undefined behavior
```

**Current Code**:
```swift
@MainActor
func updateState() {
    nonisolatedFunction()  // ⚠️ Might access MainActor state
}
```

**Issue**: 
- Actor isolation might be violated
- Or nonisolated function might access actor state
- Data race possible

**Fix Needed**: 
- Ensure proper isolation
- Or mark nonisolated functions correctly
- Or use MainActor.assumeIsolated carefully

---

### 9. **Task Leak on Error** ⚠️ MEDIUM

**Location**: `RecordingEngine.swift:387-390`, Various files

**Attack Vector**: 
```
1. Task created and stored
2. Error occurs
3. Task not cancelled
4. Task continues running
5. Resource leak
```

**Current Code**:
```swift
activeRecordingTask = Task {
    // ... recording ...
}
// ⚠️ If error occurs, task might not be cancelled
```

**Issue**: 
- Tasks stored but not always cancelled
- Or cancelled but not cleared
- Resource leak

**Fix Needed**: 
- Cancel tasks on error
- Or clear task references
- Or use defer to ensure cleanup

---

### 10. **Concurrent State Updates** ⚠️ HIGH

**Location**: `AppState.swift`, `RecordingState.swift`, `ProjectState.swift`

**Attack Vector**: 
```
1. Multiple async operations update state
2. Updates interleave
3. Last write wins
4. Intermediate updates lost
5. State corruption
```

**Current Code**:
```swift
@MainActor
class AppState {
    var appMode: AppMode = .recording
    // ⚠️ Multiple tasks can update this
}
```

**Issue**: 
- @MainActor prevents true concurrency
- But async operations can interleave
- State updates might not be atomic

**Fix Needed**: 
- Use state machine with guards
- Or serialize state updates
- Or use actor for state

---

### 11. **Weak Reference Not Checked** ⚠️ MEDIUM

**Location**: Various files with [weak self]

**Attack Vector**: 
```
1. Task captures [weak self]
2. Self deallocated
3. Task continues with nil self
4. Operations silently fail
5. No error indication
```

**Current Code**:
```swift
Task { [weak self] in
    guard let self = self else { return }  // ✅ Good
    // ... but what if self becomes nil during operation?
}
```

**Issue**: 
- Weak reference checked at start
- But might become nil during operation
- Should check periodically

**Fix Needed**: 
- Check weak reference periodically
- Or use strong reference for duration
- Or handle nil gracefully

---

### 12. **Task Priority Not Set** ⚠️ LOW

**Location**: Various Task creations

**Attack Vector**: 
```
1. Critical task created
2. Priority not set
3. Task might be deprioritized
4. Operation takes too long
5. Poor user experience
```

**Current Code**:
```swift
Task {
    // ... operation ...
    // ⚠️ No priority specified
}
```

**Issue**: 
- Tasks use default priority
- Critical operations might be slow
- Or non-critical operations might block

**Fix Needed**: 
- Set appropriate priorities
- Or use Task(priority:)
- Or prioritize critical operations

---

## 🛡️ FIXES NEEDED (Priority Order)

### High Priority (Stability & Safety)

1. **Cancel Tasks on Deallocation**
   - Cancel tasks in deinit (if possible)
   - Or use weak references
   - Or ensure tasks complete

2. **Protect Shared State**
   - Ensure @MainActor isolation
   - Or use actor for state
   - Or use proper synchronization

3. **Prevent Actor Isolation Violations**
   - Ensure proper isolation
   - Or mark nonisolated correctly
   - Or use MainActor.assumeIsolated carefully

4. **Serialize State Updates**
   - Use state machine with guards
   - Or serialize updates
   - Or use actor for state

### Medium Priority (Robustness)

5. **Fix Task Group Race Condition**
   - Use proper synchronization
   - Or use TaskGroup's built-in limit
   - Or track tasks properly

6. **Await MainActor Hops**
   - Await MainActor.run
   - Or use Task { @MainActor in ... }
   - Or ensure proper sequencing

7. **Check Task Cancellation**
   - Check Task.isCancelled periodically
   - Or use withTaskCancellationHandler
   - Or propagate cancellation

8. **Cancel Tasks on Error**
   - Cancel tasks on error
   - Or clear task references
   - Or use defer to ensure cleanup

9. **Check Weak References Periodically**
   - Check weak reference during operation
   - Or use strong reference for duration
   - Or handle nil gracefully

### Low Priority (Polish)

10. **Set Task Priorities**
    - Set appropriate priorities
    - Or use Task(priority:)
    - Or prioritize critical operations

11. **Wait for Task Groups**
    - Ensure all tasks complete
    - Or handle early return
    - Or wait for all tasks

12. **Handle Nonisolated Properties**
    - Ensure safe access patterns
    - Or use MainActor.assumeIsolated
    - Or document requirements

---

## 📋 NEXT STEPS

1. Implement high-priority fixes
2. Test concurrency scenarios
3. All 8 pieces complete!

---

**Status**: Analysis Complete - Ready for Fixes


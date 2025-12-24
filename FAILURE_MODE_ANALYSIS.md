# Failure Mode Analysis
## Comprehensive Analysis of Known Issues and Patterns
## Date: 2025-12-24

---

## 🚨 Critical Failure Modes

### 1. Signal 11 (SIGSEGV) - Window Management

#### Known Issue
- **Location**: `WindowManager.restoreMainWindow()`, `PiPCameraWindow.close()`
- **Trigger**: Ending screen sharing
- **Root Cause**: Zombie object access, improper window deallocation order
- **Status**: ✅ Fixed (but monitor for regressions)

#### Pattern
```
Screen Share Start → Screen Share Stop → Window Cleanup → Signal 11
```

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "signal.*11\|segfault"
```

#### Mitigation
- ✅ Proper window deallocation order
- ✅ Weak references where appropriate
- ✅ Guard against concurrent execution
- ⚠️ **Monitor**: Check for similar patterns in other window operations

---

### 2. Security Scope Leaks

#### Known Issue
- **Location**: `ProjectState.updateCurrentProject()`
- **Trigger**: Changing projects
- **Root Cause**: Previous security scope not stopped before creating new one
- **Status**: ✅ Fixed (but monitor for similar issues)

#### Pattern
```
Project A → Security Scope A → Project B → Security Scope B (Scope A not stopped)
```

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "security.*scope\|file.*access"
```

#### Mitigation
- ✅ Always stop previous scope before creating new one
- ⚠️ **Monitor**: Check all security scope usage points

---

### 3. Permission Request Race Conditions

#### Known Issue
- **Location**: `AppState.toggleScreenShare()`, permission request flows
- **Trigger**: Concurrent permission requests
- **Root Cause**: Multiple async permission requests without coordination
- **Status**: ⚠️ Partially addressed (needs monitoring)

#### Pattern
```
Permission Request A → Permission Request B (concurrent) → State inconsistency
```

#### Detection
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "permission.*race\|concurrent.*permission"
```

#### Mitigation
- ✅ Guard flags to prevent concurrent execution
- ⚠️ **Monitor**: Check for permission request timing issues

---

### 4. Actor Isolation Violations

#### Known Issue
- **Location**: Various async contexts accessing @MainActor properties
- **Trigger**: Accessing UI state from non-isolated context
- **Root Cause**: Improper actor isolation handling
- **Status**: ⚠️ Ongoing (needs continuous monitoring)

#### Pattern
```
Async Task → Access @MainActor Property → Compilation Error / Runtime Crash
```

#### Detection
```bash
xcodebuild test 2>&1 | grep -i "actor.*isolat\|main.*actor"
```

#### Mitigation
- ✅ Use `@MainActor` annotation
- ✅ Use `MainActor.assumeIsolated` where safe
- ⚠️ **Monitor**: Check all async operations for proper isolation

---

### 5. Test Flakiness

#### Known Issue
- **Location**: UI tests, async state tests
- **Trigger**: Timing-dependent tests, system alerts
- **Root Cause**: Tests not waiting for async operations, not handling system prompts
- **Status**: ⚠️ Partially addressed (needs continuous improvement)

#### Pattern
```
Test → Async Operation → Test Assertion (too early) → Test Fails
```

#### Detection
- Tests that pass/fail randomly
- Tests timing out intermittently

#### Mitigation
- ✅ Proper waits for async operations
- ✅ System alert handlers
- ✅ Timeout configurations
- ⚠️ **Monitor**: Track test reliability over time

---

## 🔍 Patterns to Watch For

### Pattern 1: Permission → State Inconsistency
- **Sequence**: Permission request → Permission denied → State not updated
- **Risk**: App continues with incorrect state
- **Detection**: Check permission state after denial

### Pattern 2: Async → Synchronous Access
- **Sequence**: Async operation → Synchronous property access → Crash
- **Risk**: Thread safety violations
- **Detection**: Check for @MainActor properties accessed from async contexts

### Pattern 3: Window → Memory Leak
- **Sequence**: Create window → Close window → Window not deallocated
- **Risk**: Memory leaks over time
- **Detection**: Monitor memory usage during window operations

### Pattern 4: Combine → Subscription Leak
- **Sequence**: Subscribe to publisher → Never cancel → Memory leak
- **Risk**: Growing memory usage
- **Detection**: Check for cancellables not being stored/cancelled

### Pattern 5: Security Scope → File Access Failure
- **Sequence**: Enter security scope → Change project → File access denied
- **Risk**: User unable to access project files
- **Detection**: Check file access after project changes

---

## 🛡️ Defensive Programming Patterns

### 1. Guard Against Nil
```swift
guard let value = optionalValue else {
    // Log error
    // Handle gracefully
    return
}
```

### 2. Guard Against Concurrent Execution
```swift
guard !isProcessing else { return }
isProcessing = true
defer { isProcessing = false }
// ... operation
```

### 3. Proper Cleanup
```swift
deinit {
    // Cancel subscriptions
    // Stop security scopes
    // Close windows
    // Release resources
}
```

### 4. Error Handling
```swift
do {
    try await operation()
} catch {
    // Log error
    // Show user-friendly message
    // Recover gracefully
}
```

### 5. Actor Isolation
```swift
@MainActor
func updateUI() {
    // UI updates
}

// Or
Task { @MainActor in
    // UI updates
}
```

---

## 📊 Monitoring Checklist

After each test run, check for:

### Critical Issues
- [ ] **Signal 11 crashes**: Window management, zombie objects
- [ ] **Signal 9 kills**: Memory pressure, watchdog
- [ ] **EXC_BAD_ACCESS**: Memory access violations
- [ ] **Permission denials**: Not handled gracefully
- [ ] **Security scope leaks**: File access issues

### Warning Signs
- [ ] **Memory growth**: Potential leaks
- [ ] **Test flakiness**: Timing issues
- [ ] **Actor isolation warnings**: Concurrency issues
- [ ] **Deprecation warnings**: Future compatibility issues
- [ ] **Unused variables**: Code quality issues

### Patterns
- [ ] **Recurring crashes**: Same location, different triggers
- [ ] **Intermittent failures**: Race conditions
- [ ] **Performance degradation**: Memory leaks, inefficient code
- [ ] **State inconsistencies**: Concurrency issues

---

## 🔧 Tools for Detection

### Runtime Monitoring
```bash
# Watch logs in real-time
tail -f /tmp/sanevideo_test_monitor.log

# Monitor for specific patterns
./Scripts/SaneMaster.rb diagnose --dump | grep -E "error|warning|crash"
```

### Static Analysis
```bash
# SwiftLint
swiftlint lint

# Xcode Analyzer
xcodebuild analyze -scheme SaneVideo
```

### Memory Analysis
```bash
# Instruments
instruments -t "Allocations" -D trace.dtrace SaneVideo.app

# Leaks
instruments -t "Leaks" -D trace.dtrace SaneVideo.app
```

---

## 📝 Post-Mortem Template

### Test Run: [DATE/TIME]

#### Summary
- **Total Tests**: X
- **Passed**: Y
- **Failed**: Z
- **Crashes**: N

#### Critical Issues Found
1. [Issue description]
   - **Location**: [File:Line]
   - **Pattern**: [Pattern description]
   - **Impact**: [Impact description]
   - **Fix**: [Fix description]

#### Warnings
1. [Warning description]
   - **Location**: [File:Line]
   - **Action**: [Action needed]

#### Patterns Identified
1. [Pattern description]
   - **Frequency**: [How often]
   - **Root Cause**: [Suspected cause]
   - **Mitigation**: [Mitigation strategy]

#### Recommendations
1. [Recommendation]
2. [Recommendation]

---

**Status**: Monitoring active
**Next**: Continuous monitoring and pattern analysis


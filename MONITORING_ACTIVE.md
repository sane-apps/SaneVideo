# 🚨 ACTIVE MONITORING STATUS
## Critical Test Monitoring and Failure Detection
## Date: 2025-12-24

---

## ✅ MONITORING ACTIVE

### Test Execution
- **Status**: Running in background
- **Command**: `xcodebuild test -scheme SaneVideo -destination 'platform=macOS,arch=arm64'`
- **Log Location**: `/tmp/sanevideo_test_run.log`
- **Diagnostics**: `/tmp/sanevideo_test_monitor.log`

### Monitoring Scripts
- **Location**: `.agent/monitoring_script.sh`
- **Usage**: `./.agent/monitoring_script.sh [--continuous]`
- **Output**: `/tmp/sanevideo_monitoring/`

---

## 🔍 CRITICAL PATTERNS BEING MONITORED

### 1. Permission Issues ⚠️ HIGH PRIORITY
- **Camera Permission Denial**: Black preview, crashes
- **Microphone Permission Denial**: TCC crashes, audio failures
- **Screen Recording Permission**: Signal 11 crashes, picker not appearing
- **Permission Race Conditions**: State inconsistencies
- **Permission State Persistence**: App not recognizing granted permissions

**Detection Commands**:
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "permission\|tcc"
tail -f /tmp/sanevideo_test_run.log | grep -i "permission"
```

### 2. Crash Patterns 🚨 CRITICAL
- **Signal 11 (SIGSEGV)**: Window management, zombie objects
- **Signal 9 (SIGKILL)**: Memory pressure, watchdog
- **EXC_BAD_ACCESS**: Memory access violations
- **Known Locations**: 
  - `WindowManager.restoreMainWindow()`
  - `PiPCameraWindow.close()`
  - `AppState.toggleScreenShare()`

**Detection Commands**:
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "signal.*11\|signal.*9\|segfault\|exc_bad"
tail -f /tmp/sanevideo_test_run.log | grep -i "crash\|signal\|abort"
```

### 3. Concurrency Issues ⚠️ HIGH PRIORITY
- **Actor Isolation Violations**: @MainActor property access from async
- **Race Conditions**: Concurrent state mutations
- **Data Races**: Thread safety violations

**Detection Commands**:
```bash
xcodebuild test 2>&1 | grep -i "actor.*isolat\|race.*condition\|data.*race"
```

### 4. Memory Issues ⚠️ MEDIUM PRIORITY
- **Memory Leaks**: Security scopes, Combine subscriptions
- **Memory Pressure**: Large allocations, unbounded caches
- **Retain Cycles**: Strong reference cycles in closures

**Detection Commands**:
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "memory.*leak\|retain.*cycle"
```

### 5. Window Management Issues ⚠️ HIGH PRIORITY
- **Window Lifecycle**: Windows not closing, not restoring
- **Zombie Window References**: Accessing deallocated windows
- **Window State Inconsistencies**: State not synchronized

**Detection Commands**:
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "window\|pip\|restore"
```

### 6. Security Scope Issues ⚠️ MEDIUM PRIORITY
- **Security Scope Leaks**: Previous scope not stopped
- **File Access Failures**: Access denied after project change
- **Multiple Scopes Active**: Resource leaks

**Detection Commands**:
```bash
./Scripts/SaneMaster.rb diagnose --dump | grep -i "security.*scope\|file.*access"
```

### 7. Test Flakiness ⚠️ MEDIUM PRIORITY
- **Timing Issues**: Tests not waiting for async operations
- **System Alerts**: Permission dialogs not handled
- **Animation Delays**: UI not ready when assertions run

**Detection**: Tests that pass/fail randomly

---

## 📊 REAL-TIME MONITORING

### Watch Logs
```bash
# Test execution
tail -f /tmp/sanevideo_test_run.log

# Diagnostics
tail -f /tmp/sanevideo_test_monitor.log

# Errors only
tail -f /tmp/sanevideo_monitoring/errors_*.log

# Warnings only
tail -f /tmp/sanevideo_monitoring/warnings_*.log
```

### Check Test Status
```bash
# Check if tests are running
ps aux | grep xcodebuild | grep test

# Check test results
./Scripts/SaneMaster.rb verify
```

### Analyze Results
```bash
# Run diagnostics
./Scripts/SaneMaster.rb diagnose --dump

# Check permissions
./Scripts/SaneMaster.rb diagnose --permissions

# Full analysis
./.agent/monitoring_script.sh
```

---

## 🎯 POST-MORTEM CHECKLIST

After test completion, verify:

### Critical Issues
- [ ] **No Signal 11 crashes** (window management)
- [ ] **No Signal 9 kills** (memory pressure)
- [ ] **No EXC_BAD_ACCESS** (memory violations)
- [ ] **Permission denials handled gracefully**
- [ ] **No security scope leaks**

### Warning Signs
- [ ] **No memory growth** (potential leaks)
- [ ] **No test flakiness** (timing issues)
- [ ] **No actor isolation warnings** (concurrency)
- [ ] **No deprecation warnings** (future compatibility)
- [ ] **No unused variables** (code quality)

### Patterns
- [ ] **No recurring crashes** (same location)
- [ ] **No intermittent failures** (race conditions)
- [ ] **No performance degradation** (memory leaks)
- [ ] **No state inconsistencies** (concurrency)

---

## 📝 DOCUMENTATION CREATED

1. **TEST_MONITORING_AND_ANALYSIS.md** - Comprehensive monitoring guide
2. **FAILURE_MODE_ANALYSIS.md** - Known failure modes and patterns
3. **PERMISSION_FAILURE_MODES.md** - Permission-specific issues
4. **TEST_COVERAGE_REPORT.md** - Test coverage summary
5. **MONITORING_ACTIVE.md** - This document

---

## 🚨 IMMEDIATE ACTIONS IF ISSUES FOUND

### If Signal 11 Crash Detected
1. Check window management code
2. Verify window deallocation order
3. Check for zombie object access
4. Review `WindowManager` and `PiPCameraWindow`

### If Permission Issue Detected
1. Check permission status handling
2. Verify error messages shown to user
3. Check for permission state inconsistencies
4. Review `PermissionManager` and service initialization

### If Memory Issue Detected
1. Check for security scope leaks
2. Verify Combine subscriptions cancelled
3. Check for retain cycles
4. Review memory usage patterns

### If Test Flakiness Detected
1. Add proper waits for async operations
2. Handle system alerts
3. Account for animation delays
4. Review test timing

---

## 📞 KEY FILES TO REVIEW

### Critical Code
- `SaneVideo/State/WindowManager.swift` - Window lifecycle
- `SaneVideo/Windows/PiPCameraWindow.swift` - PiP window cleanup
- `SaneVideo/State/AppState+Actions.swift` - Screen share toggle
- `SaneVideo/Services/Permissions/PermissionManager.swift` - Permission handling
- `SaneVideo/State/ProjectState.swift` - Security scope management

### Error Handling
- `SaneVideo/Core/AppError.swift` - Error definitions
- `SaneVideo/Core/Utilities/ErrorRecovery.swift` - Recovery strategies
- `SaneVideo/Core/Utilities/ErrorPresenter.swift` - Error presentation

### Test Files
- `SaneVideoTests/StateMachineVerificationTests.swift` - State machine tests
- `SaneVideoUITests/UserWorkflowTests.swift` - Workflow tests
- `SaneVideoUITests/ComprehensiveVisualTests.swift` - UI tests

---

## 🔧 TOOLS AVAILABLE

### SaneMaster.rb
```bash
./Scripts/SaneMaster.rb diagnose --dump    # Full diagnostics
./Scripts/SaneMaster.rb diagnose --permissions  # Permission status
./Scripts/SaneMaster.rb verify            # Build and test
./Scripts/SaneMaster.rb doctor            # Health check
```

### Monitoring Script
```bash
./.agent/monitoring_script.sh            # One-time analysis
./.agent/monitoring_script.sh --continuous  # Continuous monitoring
```

### System Tools
```bash
# Check system logs
log show --predicate 'process == "SaneVideo"' --last 1h

# Check permissions
tccutil reset Camera
tccutil reset Microphone
tccutil reset ScreenCapture
```

---

## ✅ STATUS SUMMARY

- ✅ **Monitoring Active**: Tests running, logs being captured
- ✅ **Documentation Complete**: All failure modes documented
- ✅ **Detection Scripts Ready**: Monitoring scripts in place
- ✅ **Analysis Tools Available**: SaneMaster.rb, monitoring scripts
- ⏳ **Awaiting Results**: Tests in progress, analysis pending

---

**NEXT**: Review test results when complete, analyze patterns, create post-mortem report

**CRITICAL**: Watch for Signal 11 crashes, permission issues, and concurrency violations


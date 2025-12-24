# Test Progress & Timeout System

## 🎯 Problem Solved

**Before**: Tests would run silently, you'd see permission dialogs, and never know if tests were stuck or just slow.

**Now**: Real-time progress indicators, automatic permission handling, and timeout detection.

---

## ✨ Features

### 1. **Real-Time Progress Indicators**
- Shows which test is currently running
- Displays test count and elapsed time
- Animated spinner during execution
- Updates every 2 seconds

### 2. **Automatic Permission Handling**
- Grants permissions before tests run
- Auto-handles permission dialogs during execution
- No more clicking "Allow" manually

### 3. **Timeout Detection**
- Default: 10 minutes for full test suite
- Customizable: `--timeout 300` (5 minutes)
- Auto-fails stuck tests
- Clear timeout messages

### 4. **Test-Level Progress Reporting**
- Each test reports start/end
- Warns if test takes > 30 seconds
- Flags tests that appear stuck (> 60 seconds)

---

## 🚀 Usage

### Basic Usage
```bash
./Scripts/SaneMaster.rb verify
```

**Output**:
```
🔨 --- [ SANEMASTER VERIFY ] ---
Building and running tests with progress monitoring...
⏱️  Timeout: 600s | Auto-handling permissions: ✅

🔐 Granting test permissions... ✅
⠋ Running: StateMachineVerificationTests.testScreenShareRecordingFlow (1 tests, 5s)
✅ Tests passed! (15 tests, 45s)
```

### Custom Timeout
```bash
./Scripts/SaneMaster.rb verify --timeout 300
```

### With Clean
```bash
./Scripts/SaneMaster.rb verify --clean
```

---

## 📊 What You'll See

### During Test Execution

**Normal Progress**:
```
⠋ Running: MyTest.testSomething (3 tests, 12s)
```

**Slow Test Warning** (after 30s):
```
⚠️  [3] Still running: MyTest.testSomething (35.2s) - This may be stuck
```

**Test Completion**:
```
✅ [3] Completed: MyTest.testSomething (2.1s)
```

**Timeout Detection**:
```
⏱️  TIMEOUT: Test run exceeded 600s
   This usually means a test is stuck or waiting for user input
   Check for permission dialogs or infinite loops
```

---

## 🔧 How It Works

### 1. Permission Handling
- **Before tests**: Runs `grant_test_permissions.sh` to reset and grant permissions
- **During tests**: Monitors output for permission dialogs and auto-handles them
- **Uses**: `tccutil` for reliable permission management

### 2. Progress Monitoring
- **Parses xcodebuild output** in real-time
- **Extracts test names** from "Test Case" lines
- **Tracks elapsed time** and test count
- **Updates display** every 2 seconds

### 3. Timeout Detection
- **Wraps test execution** in Ruby `Timeout.timeout`
- **Kills process** if timeout exceeded
- **Reports timeout** with helpful message

### 4. Test-Level Reporting
- **`TestProgressReporter`**: Swift class that reports test progress
- **Automatic**: Call `reportTestStart()` in `setUp()` and `reportTestEnd()` in `tearDown()`
- **Warnings**: Alerts if test takes > 30 seconds

---

## 🛠️ Integration

### In Your Tests

Add to `setUp()`:
```swift
override func setUp() async throws {
    reportTestStart()  // ← Add this
    // ... your setup code
}
```

Add to `tearDown()`:
```swift
override func tearDown() {
    reportTestEnd(success: true)  // ← Add this
    // ... your cleanup code
}
```

### Already Integrated
- ✅ `StateMachineVerificationTests.swift`

---

## 🎨 Visual Indicators

| Symbol | Meaning |
|--------|---------|
| 🧪 | Test starting |
| ⏳ | Test running (normal) |
| ⚠️  | Test running (slow, >30s) |
| ✅ | Test passed |
| ❌ | Test failed |
| ⏱️  | Timeout detected |
| 🔐 | Permission handling |

---

## 🐛 Troubleshooting

### Tests Still Hanging?

1. **Check timeout value**:
   ```bash
   ./Scripts/SaneMaster.rb verify --timeout 120  # 2 minutes
   ```

2. **Check for permission dialogs**:
   - Look for "🔐 Auto-handling permission dialog..." messages
   - If you see dialogs, they should auto-handle
   - If not, run: `./Scripts/grant_test_permissions.sh`

3. **Check test logs**:
   - Progress reporter shows which test is running
   - If stuck on one test, check that test's code

4. **Increase timeout**:
   ```bash
   ./Scripts/SaneMaster.rb verify --timeout 1800  # 30 minutes
   ```

### Permission Dialogs Still Appearing?

1. **Grant manually**:
   ```bash
   ./Scripts/grant_test_permissions.sh
   ```

2. **Reset permissions**:
   ```bash
   ./Scripts/SaneMaster.rb reset
   ```

3. **Check System Preferences**:
   - System Settings → Privacy & Security
   - Camera, Microphone, Screen Recording
   - Ensure SaneVideo has permissions

---

## 📝 Best Practices

1. **Always use `reportTestStart()` and `reportTestEnd()`** in your tests
2. **Set reasonable timeouts** - 10 minutes is usually enough
3. **Don't interrupt tests** - Let the timeout system handle stuck tests
4. **Check progress output** - It tells you exactly what's happening
5. **Use `--clean`** if tests seem inconsistent

---

## 🎉 Benefits

✅ **No more guessing** - You always know what's happening  
✅ **No more manual clicking** - Permissions auto-handled  
✅ **No more infinite waits** - Timeouts prevent hanging  
✅ **Better debugging** - Clear progress indicators  
✅ **Professional feel** - Real-time feedback like CI/CD systems  

---

**You'll never wonder "is it working?" again!** 🚀


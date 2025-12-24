# Testing Best Practices for SaneVideo
## Comprehensive Guide Based on Apple Documentation and Industry Standards
## Date: 2025-12-24

---

## Table of Contents

1. [Testing Framework Selection](#testing-framework-selection)
2. [Test Structure Patterns](#test-structure-patterns)
3. [Common Patterns and Anti-Patterns](#common-patterns-and-anti-patterns)
4. [Async/Await Testing](#asyncawait-testing)
5. [UI Testing Best Practices](#ui-testing-best-practices)
6. [Test Generation Tool](#test-generation-tool)
7. [Known Issues and Solutions](#known-issues-and-solutions)
8. [Apple SDK References](#apple-sdk-references)

---

## Testing Framework Selection

### Swift Testing Framework (Recommended for New Tests)

**When to Use:**
- New test files
- Modern Swift concurrency (async/await)
- Better error messages
- Structured test organization

**Pattern:**
```swift
import Testing
@testable import SaneVideo

@Suite("Feature Tests")
@MainActor
struct FeatureTests {
    @Test("Test description")
    func testFeature() async throws {
        // Arrange
        let sut = Feature()
        
        // Act
        let result = await sut.doSomething()
        
        // Assert
        #expect(result == expected)
    }
}
```

### XCTest Framework (Legacy Support)

**When to Use:**
- Existing test files
- Performance tests
- UI tests (XCUITest)
- When Swift Testing isn't available

**Pattern:**
```swift
import XCTest
@testable import SaneVideo

@MainActor
final class FeatureTests: XCTestCase {
    var sut: Feature!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        if #available(macOS 13.0, *) {
            executionTimeAllowance = 60.0
        }
        sut = Feature()
    }
    
    func testFeature() async throws {
        // Arrange-Act-Assert
        let result = await sut.doSomething()
        XCTAssertEqual(result, expected)
    }
}
```

---

## Test Structure Patterns

### AAA Pattern (Arrange-Act-Assert)

**Always follow this structure:**

```swift
@Test("Feature: Description")
func testFeature() async throws {
    // ARRANGE: Set up test conditions
    let sut = Feature()
    let input = "test"
    
    // ACT: Execute the code under test
    let result = await sut.process(input)
    
    // ASSERT: Verify the outcome
    #expect(result == "expected")
}
```

### Test Isolation

**Critical Rules:**
1. **No shared state** between tests
2. **Each test is independent** - can run in any order
3. **Clean up in tearDown** - don't rely on test order

```swift
@MainActor
struct IsolatedTests {
    // ❌ BAD: Shared state
    static var sharedCounter = 0
    
    // ✅ GOOD: Instance state
    var counter = 0
    
    @Test("Test 1")
    func test1() {
        counter = 1
        #expect(counter == 1)
    }
    
    @Test("Test 2")
    func test2() {
        // This test doesn't depend on test1
        counter = 2
        #expect(counter == 2)
    }
}
```

### Test Naming Conventions

**Format:** `test<Feature><Scenario><ExpectedResult>`

**Examples:**
- ✅ `testRecordingStartEntersPreparingState()`
- ✅ `testStopRecordingCleansUpState()`
- ✅ `testMagicFixRemovesSilence()`
- ❌ `test1()`
- ❌ `testRecording()`

**For Swift Testing:**
- Use descriptive `@Test("Feature: Scenario")` annotations

---

## Common Patterns and Anti-Patterns

### ✅ DO: Use TestEnvironment

```swift
// ✅ GOOD: Use TestEnvironment for assets
let testVideo = TestEnvironment.mockAssetURL
if FileManager.default.fileExists(atPath: testVideo.path) {
    // Use real asset
} else {
    // Fallback to temporary file
}
```

### ❌ DON'T: Hard-code paths

```swift
// ❌ BAD: Hard-coded path
let video = URL(fileURLWithPath: "/Users/sj/Videos/test.mp4")
```

### ✅ DO: Mock External Dependencies

```swift
// ✅ GOOD: Mock service
class MockCameraService: CameraServiceProtocol {
    func start() async throws { }
    func stop() { }
}

let sut = Feature(cameraService: MockCameraService())
```

### ❌ DON'T: Use Real Services in Unit Tests

```swift
// ❌ BAD: Real service (requires permissions, hardware)
let sut = Feature(cameraService: ServiceContainer.shared.cameraService)
```

### ✅ DO: Use setUp/tearDown for Common Setup

```swift
override func setUpWithError() throws {
    continueAfterFailure = false
    if #available(macOS 13.0, *) {
        executionTimeAllowance = 60.0
    }
    sut = Feature()
}

override func tearDownWithError() throws {
    sut = nil
}
```

### ❌ DON'T: Repeat setup in every test

```swift
// ❌ BAD: Repeated setup
func test1() {
    let sut = Feature()
    // ...
}

func test2() {
    let sut = Feature() // Repeated!
    // ...
}
```

---

## Async/Await Testing

### Swift Testing Framework

```swift
@Test("Async operation")
func testAsyncOperation() async throws {
    // ✅ GOOD: Direct async/await
    let result = try await service.performAsyncOperation()
    #expect(result != nil)
}
```

### XCTest Framework

```swift
func testAsyncOperation() async throws {
    // ✅ GOOD: async throws
    let result = try await service.performAsyncOperation()
    XCTAssertNotNil(result)
}

// For completion handlers, use withCheckedContinuation
func testCompletionHandler() async {
    await withCheckedContinuation { continuation in
        service.performOperation { result in
            XCTAssertNotNil(result)
            continuation.resume()
        }
    }
}
```

### ⚠️ Common Pitfalls

**❌ DON'T: Use sleep() for async operations**
```swift
// ❌ BAD
func testAsync() {
    service.start()
    sleep(1) // Unreliable!
    XCTAssertTrue(service.isReady)
}
```

**✅ DO: Use proper async/await or expectations**
```swift
// ✅ GOOD
func testAsync() async throws {
    try await service.start()
    #expect(service.isReady)
}
```

---

## UI Testing Best Practices

### Setup

```swift
override func setUpWithError() throws {
    continueAfterFailure = false
    
    if #available(macOS 13.0, *) {
        executionTimeAllowance = 300.0 // 5 minutes for UI tests
    }
    
    app = XCUIApplication()
    app.launchArguments = ["-uitesting", "-ui_testing", "YES"]
    app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
}
```

### Element Identification

**✅ DO: Use accessibility identifiers**
```swift
// In your SwiftUI view:
Button("Record") {
    // ...
}
.accessibilityIdentifier("RecordButton")

// In test:
let recordButton = app.buttons["RecordButton"]
XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
```

**❌ DON'T: Rely on labels or positions**
```swift
// ❌ BAD: Fragile
let button = app.buttons["Record"] // Breaks if label changes
let button = app.buttons.firstMatch // Unreliable
```

### Waiting for Elements

**✅ DO: Use waitForExistence with timeout**
```swift
let element = app.buttons["RecordButton"]
guard element.waitForExistence(timeout: 10) else {
    XCTFail("Record button not found")
    return
}
element.tap()
```

**❌ DON'T: Use sleep() or fixed delays**
```swift
// ❌ BAD
sleep(2) // Unreliable timing
app.buttons["RecordButton"].tap()
```

### System Alerts and Permissions

**✅ DO: Handle system alerts**
```swift
addUIInterruptionMonitor(withDescription: "System Alerts") { alert in
    if alert.buttons["Allow"].exists {
        alert.buttons["Allow"].tap()
        return true
    }
    return false
}
```

**✅ DO: Wait for app to be ready**
```swift
func waitForAppReady(timeout: TimeInterval = 15) -> Bool {
    app.launch()
    app.activate()
    handleSystemAlerts()
    return app.windows.firstMatch.waitForExistence(timeout: timeout)
}
```

---

## Test Generation Tool

### Usage

```bash
# Generate unit test with Swift Testing framework
./Scripts/SaneMaster.rb gen_test MyFeatureTests --target MyFeature

# Generate UI test with XCTest
./Scripts/SaneMaster.rb gen_test MyUITests --type ui --framework xctest

# Generate async test
./Scripts/SaneMaster.rb gen_test AsyncTests --async
```

### Generated Template Includes

1. ✅ Proper imports
2. ✅ @MainActor annotation
3. ✅ Test timeout configuration
4. ✅ setUp/tearDown (XCTest) or computed properties (Testing)
5. ✅ AAA pattern examples
6. ✅ Helper method templates
7. ✅ TestEnvironment usage

---

## Known Issues and Solutions

### Issue 1: Tests Not Discovered

**Symptoms:**
- Tests show "0 tests executed"
- Test file exists but doesn't run

**Solutions:**
1. Run `xcodegen generate` after creating test file
2. Ensure test file is in correct target (`SaneVideoTests` or `SaneVideoUITests`)
3. Check that test class/struct is not private
4. For Swift Testing: Ensure `@Suite` or `@Test` annotations are present

### Issue 2: Flaky Tests

**Symptoms:**
- Tests pass/fail randomly
- Timing-dependent failures

**Solutions:**
1. **Never use sleep()** - use `waitForExistence(timeout:)` or async/await
2. **Set explicit timeouts** - don't rely on defaults
3. **Isolate test state** - no shared mutable state
4. **Use expectations** instead of polling loops

```swift
// ❌ BAD: Flaky
while !service.isReady {
    sleep(0.1)
}

// ✅ GOOD: Reliable
let expectation = expectation(description: "Service ready")
service.onReady = { expectation.fulfill() }
wait(for: [expectation], timeout: 5)
```

### Issue 3: Permission Dialogs Blocking Tests

**Symptoms:**
- Tests hang waiting for permission dialogs
- UI tests fail on first run

**Solutions:**
1. **Use UI interruption monitor**
2. **Pre-grant permissions** in test setup
3. **Use test environment flags** to skip permission checks

```swift
app.launchArguments = ["-uitesting", "-skip_permissions"]
```

### Issue 4: Async Operations Not Completing

**Symptoms:**
- Tests finish before async work completes
- Race conditions

**Solutions:**
1. **Use async/await** instead of completion handlers
2. **Await all async operations**
3. **Use Task.yield()** to allow async work to start

```swift
// ✅ GOOD
func testAsync() async throws {
    service.start()
    await Task.yield() // Allow async work to start
    try await service.waitForCompletion()
    #expect(service.isComplete)
}
```

---

## Apple SDK References

### Official Documentation

1. **XCTest Framework**
   - https://developer.apple.com/documentation/xctest
   - Testing framework for unit and UI tests

2. **Swift Testing Framework**
   - https://developer.apple.com/documentation/testing
   - Modern testing framework (macOS 15.0+)

3. **XCUITest**
   - https://developer.apple.com/documentation/xctest/xcuitest
   - UI testing framework

4. **Testing Best Practices**
   - https://developer.apple.com/documentation/xctest/xctestcase
   - XCTestCase documentation with best practices

### Key Concepts

1. **Test Discovery**
   - XCTest: Methods starting with `test`
   - Swift Testing: `@Test` annotation

2. **Async Testing**
   - XCTest: `async throws` functions
   - Swift Testing: `async throws` functions

3. **Timeouts**
   - XCTest: `executionTimeAllowance` (macOS 13.0+)
   - Swift Testing: Built-in timeout handling

4. **Test Organization**
   - XCTest: `XCTestCase` subclasses
   - Swift Testing: `@Suite` annotations

---

## Quick Reference Checklist

### Before Writing Tests

- [ ] Choose framework (Swift Testing preferred for new tests)
- [ ] Identify what to test (unit vs integration vs UI)
- [ ] Plan test cases (happy path, edge cases, error cases)
- [ ] Identify dependencies to mock

### Writing Tests

- [ ] Follow AAA pattern (Arrange-Act-Assert)
- [ ] Use descriptive test names
- [ ] Set appropriate timeouts
- [ ] Mock external dependencies
- [ ] Use TestEnvironment for assets
- [ ] Handle async operations properly
- [ ] Add accessibility identifiers for UI tests

### After Writing Tests

- [ ] Run tests: `./Scripts/SaneMaster.rb verify`
- [ ] Check diagnostics: `./Scripts/SaneMaster.rb diagnose --dump`
- [ ] Verify test isolation (can run in any order)
- [ ] Document any known limitations

---

## Tools and Commands

### Test Generation
```bash
./Scripts/SaneMaster.rb gen_test <name> [options]
```

### Running Tests
```bash
./Scripts/SaneMaster.rb verify          # Build + test
./Scripts/SaneMaster.rb verify --clean    # Clean build + test
```

### Diagnostics
```bash
./Scripts/SaneMaster.rb diagnose --dump  # Full diagnostics
./Scripts/SaneMaster.rb doctor           # Health check
```

### Test Assets
```bash
./Scripts/SaneMaster.rb gen_assets       # Generate test media
```

---

**Last Updated:** 2025-12-24  
**Based on:** Apple XCTest/Swift Testing documentation, industry best practices, SaneVideo codebase patterns


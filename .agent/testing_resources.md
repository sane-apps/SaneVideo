# Testing Resources for AI Agents
## Quick Reference for Test Generation and Best Practices

## Test Generation Command

```bash
./Scripts/SaneMaster.rb gen_test <TestName> [options]
```

**Options:**
- `--type <unit|ui>` - Test type (default: unit)
- `--framework <xctest|testing>` - Framework (default: testing)
- `--target <ClassName>` - Target class/service to test
- `--async` - Include async/await patterns

**Examples:**
```bash
# Unit test for a service
./Scripts/SaneMaster.rb gen_test CameraServiceTests --target CameraService

# UI test
./Scripts/SaneMaster.rb gen_test RecordingUITests --type ui --framework xctest

# Async test
./Scripts/SaneMaster.rb gen_test AsyncOperationTests --async
```

## Testing Framework Selection

### Swift Testing (Recommended)
- Modern, better error messages
- Better async/await support
- Use `@Test` and `#expect`

### XCTest (Legacy/UI)
- Required for UI tests (XCUITest)
- Use `XCTAssert*` assertions
- Better for performance tests

## Common Patterns

### AAA Pattern (Always Use)
```swift
@Test("Feature: Description")
func testFeature() async throws {
    // ARRANGE: Set up
    let sut = Feature()
    
    // ACT: Execute
    let result = await sut.doSomething()
    
    // ASSERT: Verify
    #expect(result == expected)
}
```

### Test Isolation
- No shared state between tests
- Each test independent
- Clean up in tearDown

### Async Testing
```swift
// ✅ GOOD: Direct async/await
func testAsync() async throws {
    let result = try await service.perform()
    #expect(result != nil)
}

// ❌ BAD: sleep() or fixed delays
func testAsync() {
    service.start()
    sleep(1) // Unreliable!
}
```

## Test Environment

**Always use TestEnvironment for assets:**
```swift
let testVideo = TestEnvironment.mockAssetURL
if FileManager.default.fileExists(atPath: testVideo.path) {
    // Use real asset
} else {
    // Fallback to temporary file
}
```

## UI Testing

**Setup:**
```swift
override func setUpWithError() throws {
    continueAfterFailure = false
    if #available(macOS 13.0, *) {
        executionTimeAllowance = 300.0 // 5 min for UI
    }
    app = XCUIApplication()
    app.launchArguments = ["-uitesting", "-ui_testing", "YES"]
}
```

**Element Identification:**
- ✅ Use `accessibilityIdentifier`
- ❌ Don't rely on labels or positions

**Waiting:**
- ✅ Use `waitForExistence(timeout:)`
- ❌ Never use `sleep()`

## Common Issues

### Tests Not Discovered
1. Run `xcodegen generate` after creating test file
2. Ensure file is in correct target
3. Check test class/struct is not private

### Flaky Tests
1. Never use `sleep()` - use `waitForExistence` or async/await
2. Set explicit timeouts
3. Isolate test state
4. Use expectations instead of polling

### Permission Dialogs
1. Use UI interruption monitor
2. Pre-grant permissions in setup
3. Use test environment flags

## Documentation

- **Full Guide:** `TESTING_BEST_PRACTICES.md`
- **SOP:** `DEVELOPMENT.md` Section 8
- **Apple Docs:** https://developer.apple.com/documentation/xctest

## Quick Checklist

Before writing tests:
- [ ] Choose framework (Swift Testing preferred)
- [ ] Identify test type (unit/integration/UI)
- [ ] Plan test cases
- [ ] Identify dependencies to mock

Writing tests:
- [ ] Follow AAA pattern
- [ ] Use descriptive names
- [ ] Set timeouts
- [ ] Mock dependencies
- [ ] Use TestEnvironment
- [ ] Handle async properly

After writing:
- [ ] Run: `./Scripts/SaneMaster.rb verify`
- [ ] Check: `./Scripts/SaneMaster.rb diagnose --dump`
- [ ] Verify isolation


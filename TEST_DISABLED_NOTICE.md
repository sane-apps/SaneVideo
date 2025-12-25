# Test Execution Status

## Status: ⚠️ Tests Disabled (Temporary)

**Date**: 2025-12-25  
**Reasons**: 
1. **Local**: SwiftUICore linker error in Xcode 16/macOS 26.2
2. **CI**: Deployment target mismatch (see `CI_TEST_STATUS.md`)

## What Happened

Test targets (`SaneVideoTests` and `SaneVideoUITests`) are temporarily disabled in the build scheme due to a linker error:

```
cannot link directly with 'SwiftUICore' because product being built is not an allowed client of it
```

This is a **known bug in Xcode 16/macOS 26.2** where SwiftUICore (a private framework) cannot be linked by test targets.

## Impact

- ✅ **Main app builds and runs successfully**
- ❌ **Tests cannot run** (blocked by linker error)
- ✅ **All test files are preserved** (not deleted)

## Current Status

- Test targets are commented out in `project.yml`
- Test files remain in the codebase
- `./Scripts/SaneMaster.rb verify` builds the app only (skips tests)

## How to Re-enable Tests

When Xcode is updated and the bug is fixed:

1. Open `project.yml`
2. Find the `test:` section under `schemes: SaneVideo:`
3. Uncomment the test targets:
   ```yaml
   test:
     targets:
       - SaneVideoTests
       - SaneVideoUITests
   ```
4. Also uncomment in the `build:` section:
   ```yaml
   build:
     targets:
       SaneVideo: all
       SaneVideoTests: [test]
   ```
5. Run `xcodegen generate`
6. Run `./Scripts/SaneMaster.rb verify` to test

## Alternative Testing Methods

Since automated test execution is disabled, use these tools:

1. **Static Analysis**:
   ```bash
   ./Scripts/SaneMaster.rb validate_test_references  # Verify UI test references
   ./Scripts/SaneMaster.rb check_deprecations         # Find deprecated APIs
   ./Scripts/SaneMaster.rb dead_code                  # Find unused code
   ./Scripts/SaneMaster.rb lint                       # Code quality
   ```

2. **API Verification**:
   ```bash
   ./Scripts/SaneMaster.rb verify_api <APIName> [Framework]
   ```

3. **Build Verification**:
   ```bash
   ./Scripts/SaneMaster.rb verify  # Builds app (tests skipped)
   ```

4. **Manual Testing**: Run the app and test features manually

## CI Status

Tests are also disabled in CI due to deployment target mismatch. See `CI_TEST_STATUS.md` for details.

## References

- Issue documented in `DEVELOPMENT.md` (Troubleshooting section)
- Test files preserved in:
  - `SaneVideoTests/` (unit tests)
  - `SaneVideoUITests/` (UI tests)


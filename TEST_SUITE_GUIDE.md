# Comprehensive Test Suite Guide

## Overview

The `test_suite` command orchestrates all available validation tools into a unified testing workflow. This provides a comprehensive alternative to automated test execution while tests are disabled.

## Usage

```bash
./Scripts/SaneMaster.rb test_suite [options]
```

### Options

- `--quick`: Fast checks only (~30 seconds)
  - Build verification
  - XcodeGen sync
  - Linting
  - Test reference validation
  - Documentation sync
  
- `--full`: All checks including slow ones (~5 minutes)
  - All quick checks
  - Mock verification
  - Deprecation checking
  - Dead code detection

- `--ci`: CI-optimized mode
  - All quick checks
  - Mock verification
  - Deprecation checking
  - Excludes slow checks (dead code)
  - Warnings don't fail CI

## What It Checks

### Phase 1: Fast Validation (Always Runs)

1. **Build Verification**
   - Ensures code compiles
   - Catches compilation errors early
   - **Critical**: Fails suite if build fails

2. **XcodeGen Project Sync**
   - Verifies `project.yml` matches `project.pbxproj`
   - Prevents project file drift
   - **Warning**: Non-blocking

3. **Code Linting**
   - SwiftLint style checks
   - Auto-fixable issues
   - **Warning**: Non-blocking

4. **Test Reference Validation**
   - Verifies UI test references match UI code
   - Prevents broken test references
   - **Critical**: Fails suite if mismatches found

5. **Documentation Sync**
   - Ensures docs match tool capabilities
   - Prevents documentation drift
   - **Warning**: Non-blocking

6. **Protocol Changes** (if files provided)
   - Detects protocol changes that need mock regeneration
   - **Warning**: Non-blocking

### Phase 2: Medium Validation (Unless `--quick`)

7. **Mock Synchronization**
   - Verifies mocks match protocols
   - Prevents outdated mocks
   - **Warning**: Non-blocking

8. **Deprecation Checking** (requires `--full` or `--ci`)
   - Finds deprecated API usage
   - Helps maintain compatibility
   - **Warning**: Non-blocking

### Phase 3: Deep Analysis (Only `--full`)

9. **Dead Code Detection**
   - Finds unused code using Periphery
   - Helps keep codebase lean
   - **Warning**: Non-blocking

## Output Format

The suite provides:
- ✅ **Passed**: Checks that succeeded
- ❌ **Failed**: Critical checks that failed (suite fails)
- ⚠️ **Warnings**: Non-critical issues (suite passes)
- ⏭️ **Skipped**: Checks not run in current mode

## Exit Codes

- `0`: All checks passed (warnings allowed)
- `1`: One or more critical checks failed

## Integration

### Pre-Commit Hook

Add to `lefthook.yml`:
```yaml
pre-commit:
  commands:
    test_suite:
      run: ./Scripts/SaneMaster.rb test_suite --quick
```

### CI Integration

Already integrated in `.github/workflows/ci.yml`:
```yaml
- name: Run Comprehensive Test Suite
  run: ./Scripts/SaneMaster.rb test_suite --ci
```

### Local Development

**Before every commit**:
```bash
./Scripts/SaneMaster.rb test_suite --quick
```

**Before releases**:
```bash
./Scripts/SaneMaster.rb test_suite --full
```

## Benefits

1. **Unified Interface**: One command for all validation
2. **Phased Execution**: Fast checks first, slow checks optional
3. **Clear Reporting**: Summary of all checks in one place
4. **CI Ready**: Exit codes and `--ci` mode for automation
5. **Comprehensive**: Covers all aspects of code quality

## Comparison to Automated Tests

| Aspect | Automated Tests | Test Suite |
|--------|----------------|------------|
| Runtime Behavior | ✅ Yes | ❌ No |
| Static Analysis | ❌ No | ✅ Yes |
| Code Quality | ❌ No | ✅ Yes |
| API Validation | ❌ No | ✅ Yes |
| Test Sync | ❌ No | ✅ Yes |
| Speed | Slow (30s-5min) | Fast (30s-5min) |
| Environment | Requires macOS 26.2 | Works now |

## When Tests Are Re-enabled

The test suite will complement (not replace) automated tests:
- **Test Suite**: Static analysis, code quality, validation
- **Automated Tests**: Runtime behavior, integration, performance

Both will run in CI and local workflows.


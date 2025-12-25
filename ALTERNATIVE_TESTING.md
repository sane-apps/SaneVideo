# Alternative Testing Methods

Since automated test execution is currently disabled, use these tools to validate code quality and catch issues.

## Available Tools

### 1. Test Reference Validation

**Purpose**: Ensures UI test code references match actual UI elements

```bash
./Scripts/SaneMaster.rb validate_test_references
```

**What it does**:
- Scans all UI test files for accessibility identifier references
- Verifies identifiers exist in UI code
- Prevents tests from referencing non-existent UI elements

**When to use**: Before committing UI changes or test updates

### 2. Deprecation Checking

**Purpose**: Finds deprecated API usage

```bash
./Scripts/SaneMaster.rb check_deprecations
```

**What it does**:
- Builds the project
- Parses build warnings for deprecation notices
- Reports deprecated APIs that need updating

**When to use**: Before releases, after Xcode updates

### 3. Dead Code Detection

**Purpose**: Finds unused code that can be removed

```bash
./Scripts/SaneMaster.rb dead_code
```

**What it does**:
- Uses Periphery to scan for unused code
- Identifies functions, classes, properties that are never referenced
- Helps keep codebase lean

**When to use**: During refactoring, before releases

### 4. API Verification

**Purpose**: Verifies APIs exist in the SDK before using them

```bash
./Scripts/SaneMaster.rb verify_api <APIName> [Framework]
```

**Examples**:
```bash
./Scripts/SaneMaster.rb verify_api faceCaptureQuality Vision
./Scripts/SaneMaster.rb verify_api SCContentSharingPicker ScreenCaptureKit
```

**What it does**:
- Searches SDK `.swiftinterface` files for API existence
- Prevents using non-existent or incorrectly named APIs
- More reliable than web search

**When to use**: When unsure if an API exists or is correctly named

### 5. Mock Verification

**Purpose**: Ensures mocks are in sync with protocols

```bash
./Scripts/SaneMaster.rb verify_mocks
```

**What it does**:
- Checks that mock implementations match protocol requirements
- Identifies missing mock methods
- Prevents test mocks from becoming outdated

**When to use**: After protocol changes

### 6. Linting

**Purpose**: Enforces code style and catches common issues

```bash
./Scripts/SaneMaster.rb lint
```

**What it does**:
- Runs SwiftLint
- Auto-fixes common issues
- Reports style violations

**When to use**: Before committing, as part of pre-commit hooks

### 7. Build Verification

**Purpose**: Ensures code compiles

```bash
./Scripts/SaneMaster.rb verify
```

**What it does**:
- Builds the app (tests skipped when disabled)
- Catches compilation errors
- Verifies project structure

**When to use**: After code changes, before committing

### 8. Documentation Sync Check

**Purpose**: Ensures documentation matches code

```bash
./Scripts/SaneMaster.rb check_docs
```

**What it does**:
- Compares `SaneMaster.rb` commands with `DEVELOPMENT.md`
- Identifies undocumented features
- Keeps documentation accurate

**When to use**: After adding new tools or commands

### 9. Comprehensive Test Suite ⭐ **NEW**

**Purpose**: Run all validation tools in one command

```bash
./Scripts/SaneMaster.rb test_suite [--quick] [--full] [--ci]
```

**What it does**:
- Orchestrates all validation tools
- Provides unified reporting
- Phased execution (fast → medium → slow)
- Exit codes for CI integration

**Modes**:
- `--quick`: Fast checks only (~30s)
- `--full`: All checks including slow ones (~5min)
- `--ci`: CI-optimized (excludes slow checks)

**When to use**: 
- Before every commit: `test_suite --quick`
- Before releases: `test_suite --full`
- In CI: `test_suite --ci`

## Recommended Workflow

Before committing code:

```bash
# 1. Build verification
./Scripts/SaneMaster.rb verify

# 2. Static analysis
./Scripts/SaneMaster.rb validate_test_references
./Scripts/SaneMaster.rb check_deprecations
./Scripts/SaneMaster.rb lint

# 3. Dead code check (optional, before releases)
./Scripts/SaneMaster.rb dead_code
```

## What These Tools Can't Replace

These tools provide **static analysis** but cannot replace:
- **Runtime behavior testing**: Actual test execution
- **Integration testing**: End-to-end workflows
- **Performance testing**: Actual performance metrics
- **UI interaction testing**: Real user interactions

## When Tests Are Re-enabled

Once the environment supports test execution:
1. Re-enable test targets (see `TEST_DISABLED_NOTICE.md`)
2. Run `./Scripts/SaneMaster.rb verify` to execute tests
3. Continue using these tools for additional validation

## Integration with CI

These tools can be integrated into CI workflows:
- `validate_test_references` - Run in CI to catch test/UI mismatches
- `check_deprecations` - Run in CI to catch deprecated API usage
- `lint` - Already runs in CI
- `verify` - Already runs in CI (builds app)

See `.github/workflows/ci.yml` for current setup.


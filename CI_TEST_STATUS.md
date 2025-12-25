# CI Test Status

> **Status**: Current Reference  
> **Related**: See [DEVELOPMENT.md](DEVELOPMENT.md) for main SOP (section 8)  
> **Last Updated**: 2025-12-25

> **Note**: This is CI-specific. For local test status, see [TEST_DISABLED_NOTICE.md](TEST_DISABLED_NOTICE.md). For complete information, see [DEVELOPMENT.md](DEVELOPMENT.md) section 8.

## Current Status: ⚠️ Tests Disabled in CI

**Date**: 2025-12-25  
**Reason**: Deployment target mismatch between CI runners and app requirements

## The Problem

- **CI Runners**: macOS 26.0.1 (GitHub Actions)
- **App Deployment Target**: macOS 26.2
- **Test Targets**: Inherit app's deployment target (26.2)
- **Result**: Xcode blocks test execution when runner macOS < deployment target

## What Works

✅ **CI Infrastructure**: Fully functional
- Ruby 3.1 compatibility fixed
- macOS 26 runner configured
- xcodegen installation working
- Secrets.swift committed
- Build succeeds

✅ **Build Verification**: CI builds the app successfully

❌ **Test Execution**: Blocked by deployment target mismatch

## Why We Can't Fix This

1. **Xcode Limitation**: Test targets that depend on app targets inherit the app's deployment target
2. **GitHub Actions Limitation**: Only provides macOS 26.0.1 runners (not 26.2)
3. **App Requirements**: App uses macOS 26.2 features (FoundationModels, Swift 6.2, etc.)

## Options (None Viable Right Now)

1. **Lower App Target to 26.0**: ❌ Would break features requiring 26.2
2. **Wait for macOS 26.2 Runners**: ⏳ Not available yet
3. **Use Self-Hosted Runners**: ⚠️ Requires infrastructure setup

## Alternative Testing in CI

While automated test execution is disabled, CI still provides:

1. **Build Verification**: Ensures code compiles
2. **Linting**: Code quality checks (`swiftlint`)
3. **Static Analysis**: Can be added via `SaneMaster.rb` commands

## When Tests Will Work

Tests will automatically work when:
- GitHub Actions provides macOS 26.2+ runners, OR
- We lower the app deployment target (if features allow)

## Current CI Workflow

The CI workflow (`ci.yml`) is configured to:
1. ✅ Build the app
2. ⚠️ Attempt tests (fails gracefully with deployment target error)
3. ✅ Upload test results (empty, but doesn't fail CI)
4. ✅ Run health checks and documentation sync

**CI does not fail** - it reports the test limitation but continues.

## For AI Agents

**DO NOT**:
- Try to fix the deployment target mismatch (it's an environmental limitation)
- Attempt to run tests in CI (they will fail with deployment target error)
- Lower the app deployment target without user approval (may break features)

**DO**:
- Use `./Scripts/SaneMaster.rb verify` locally (builds app, skips tests)
- Use alternative testing methods (static analysis, API verification)
- Document test requirements for when environment supports them

## References

- `TEST_DISABLED_NOTICE.md` - Local test status
- `DEVELOPMENT.md` - Alternative testing methods
- `.github/workflows/ci.yml` - CI configuration


# Tools & Processes Audit
## Comprehensive Review for Determinism and Consistency
**Date**: 2025-12-24

---

## 🔴 CRITICAL CONTRADICTIONS FOUND

### 1. API Verification Rule Contradiction

**Location**: `DEVELOPMENT.md` lines 15 vs 26-31

**Problem**:
- Line 15: "If unsure about an API, **SEARCH THE WEB**. Do not guess."
- Lines 26-31: "SDK IS THE SOURCE OF TRUTH (CRITICAL): **NEVER trust web search for API existence or signatures**."

**Resolution Needed**: 
- **Line 15 should be updated** to: "If unsure about an API, **CHECK THE SDK FIRST** (see SDK verification workflow), then search the web for context/usage."

---

## ⚠️ INCONSISTENCIES FOUND

### 2. Test Execution Strategy Mismatch

**Location**: `fastlane/Fastfile` vs `Scripts/SaneMaster.rb`

**Problem**:
- `fastlane verify` **skips UI tests by default** (`skip_testing: "SaneVideoUITests"`)
- `SaneMaster.rb verify` runs **all tests** (no skip)
- `DEVELOPMENT.md` says `verify` is "Unit Tests only" but SaneMaster doesn't enforce this

**Impact**: Different behavior depending on which tool is used.

**Recommendation**: 
- Align behavior: Either both skip UI tests by default, or document the difference clearly.
- Add `--ui` flag to SaneMaster to explicitly include UI tests.

### 3. Test Asset Naming Inconsistency

**Location**: Multiple files reference `test_video.mp4` but guide says any format works

**Problem**:
- `SaneMaster.rb` doctor checks for `test_video.mp4` specifically
- `DEVELOPMENT.md` mentions `test_video.mp4` or `test_silence.mp4`
- `TEST_VIDEO_ASSETS_GUIDE.md` (deleted) said any format works
- `TestEnvironment.swift` searches for `test_video.mp4` by default

**Status**: ✅ **RESOLVED** - TestEnvironment supports any format via `TEST_ASSET_NAME` env var, but default is still `.mp4`. This is acceptable.

---

## 🟡 MISSING DETERMINISM (Hallucination Risks)

### 4. File Size Enforcement Not Automated

**Rule**: "MAX FILE SIZE = 500 LINES" (DEVELOPMENT.md line 24)

**Current State**:
- ✅ SwiftLint configured: `file_length: warning: 500, error: 800`
- ❌ **Not enforced in CI/CD** - only warns locally
- ❌ **No pre-commit hook** to block commits

**Risk**: Files can exceed 500 lines without blocking workflow.

**Recommendation**: Add to `lefthook.yml` pre-commit:
```yaml
file_size_check:
  run: swiftlint lint --strict --path {all_files} | grep -q "file_length" && exit 1 || exit 0
```

### 5. XcodeGen Enforcement Not Automated

**Rule**: "FILE CREATION = XCODEGEN: If you create a new file, run `xcodegen generate` immediately." (DEVELOPMENT.md line 23)

**Current State**:
- ❌ **No automated check** that `xcodegen generate` was run
- ❌ **No git hook** to detect new files and warn
- ❌ **No CI check** that `project.pbxproj` is in sync with `project.yml`

**Risk**: Developers/AI can forget to run xcodegen, causing build failures.

**Recommendation**: 
- Add pre-commit hook to check if new `.swift` files exist that aren't in `project.pbxproj`
- Or: Add CI check that `xcodegen generate --check` passes

### 6. SDK Verification Not Automated

**Rule**: "SDK IS THE SOURCE OF TRUTH" - Check `.swiftinterface` files (DEVELOPMENT.md line 26-31)

**Current State**:
- ✅ Workflow documented in `.agent/workflows/sdk-api-verification.md`
- ❌ **Manual process only** - requires running grep commands
- ❌ **No tool** to verify API existence programmatically

**Risk**: AI/developers may still guess or use web search instead of SDK.

**Recommendation**: 
- Add `SaneMaster.rb verify_api <APIName> [Framework]` command
- Example: `./Scripts/SaneMaster.rb verify_api faceCaptureQuality Vision`
- This would grep the SDK and return definitive yes/no + signature

### 7. Mock Synchronization Not Automated

**Current State**:
- ✅ Mockolo integration exists (`gen_mock` command)
- ✅ Protocols marked with `@mockable`
- ❌ **No check** that mocks are up-to-date with protocol changes
- ❌ **No CI check** that mocks match protocols

**Risk**: Outdated mocks can cause test failures or false positives.

**Recommendation**:
- Add `SaneMaster.rb verify_mocks` command that:
  1. Finds all `@mockable` protocols
  2. Generates temp mocks
  3. Compares with existing mocks
  4. Reports differences
- Add to pre-push hook or CI

### 8. Test Asset Discovery Could Be More Deterministic

**Current State**:
- ✅ `TestEnvironment.mockAssetURL` has fallback chain
- ✅ Supports `TEST_ASSET_NAME` env var
- ⚠️ **Multiple search paths** (env var, current dir, hardcoded, /tmp)
- ⚠️ **No validation** that asset exists before test runs

**Risk**: Tests may fail with unclear "file not found" errors.

**Recommendation**:
- Add `SaneMaster.rb verify_assets` command (part of `doctor`)
- Validate all referenced test assets exist before running tests
- Fail fast with clear error message

### 9. Protocol Changes Not Tracked

**Current State**:
- ✅ Protocols exist in `SaneVideo/Core/Protocols/`
- ✅ Marked with `@mockable` for Mockolo
- ❌ **No tracking** of when protocols change
- ❌ **No reminder** to regenerate mocks

**Risk**: Protocol changes may not trigger mock regeneration.

**Recommendation**:
- Add git hook or CI check that detects protocol file changes
- Warn if mocks weren't regenerated after protocol change

---

## ✅ WELL-DETERMINED PROCESSES

### 1. Build & Test Workflow
- ✅ `SaneMaster.rb verify` - Single command for build + test
- ✅ `SaneMaster.rb diagnose --dump` - Always shows logs
- ✅ Timeout handling (480s default)
- ✅ Permission automation

### 2. Code Quality Enforcement
- ✅ Lefthook pre-commit: SwiftLint + RuboCop
- ✅ Lefthook pre-push: Security audit + doctor + verify
- ✅ SwiftLint config: File size warnings

### 3. Test Generation
- ✅ `SaneMaster.rb gen_test` - Deterministic templates
- ✅ Supports both Swift Testing and XCTest
- ✅ Follows AAA pattern

### 4. Mock Generation
- ✅ `SaneMaster.rb gen_mock` - Automated via Mockolo
- ✅ Post-processing fixes imports and actor isolation
- ✅ Clear workflow documented

### 5. Project Structure
- ✅ `project.yml` - Single source of truth for Xcode project
- ✅ XcodeGen generates `project.pbxproj`
- ✅ Clear directory structure documented

---

## 🎯 RECOMMENDED IMPROVEMENTS (Priority Order)

### High Priority (Prevent Hallucinations)

1. **Fix API Verification Contradiction** (DEVELOPMENT.md line 15)
   - Update to: "Check SDK first, then web for context"

2. **Automate File Size Enforcement**
   - Add SwiftLint file_length check to pre-commit hook
   - Fail commit if any file > 500 lines

3. **Automate XcodeGen Verification**
   - Add pre-commit check: New `.swift` files must be in `project.pbxproj`
   - Or: Add CI check that `xcodegen generate --check` passes

4. **Add SDK API Verification Tool**
   - `SaneMaster.rb verify_api <APIName> [Framework]`
   - Returns definitive yes/no + signature from SDK

### Medium Priority (Improve Determinism)

5. **Automate Mock Synchronization Check**
   - `SaneMaster.rb verify_mocks` command
   - Compare generated mocks with existing
   - Add to pre-push or CI

6. **Standardize Test Execution**
   - Align `fastlane verify` and `SaneMaster.rb verify` behavior
   - Document when to use each

7. **Improve Test Asset Validation**
   - `SaneMaster.rb verify_assets` (enhance `doctor`)
   - Validate all test assets exist before test runs

### Low Priority (Nice to Have)

8. **Protocol Change Tracking**
   - ✅ Git hook to detect protocol changes
   - ✅ Remind to regenerate mocks

9. **Automated Documentation Sync**
   - ✅ Check that DEVELOPMENT.md matches actual tool behavior
   - ✅ CI check for documentation drift

---

## 📋 ACTION ITEMS

### Immediate (Fix Contradictions)

- [x] **Fix DEVELOPMENT.md line 15** - Update API verification rule ✅
- [x] **Document test execution difference** - Added --ui flag to verify ✅

### Short Term (Add Automation)

- [x] **Add file size enforcement** to lefthook pre-commit ✅
- [x] **Add XcodeGen verification** to pre-commit hook ✅
- [x] **Add SDK API verification tool** to SaneMaster.rb ✅

### Medium Term (Improve Determinism)

- [x] **Add mock synchronization check** to SaneMaster.rb ✅
- [x] **Standardize test execution** - Added --ui flag, matches fastlane behavior ✅
- [x] **Enhance asset validation** in doctor command ✅

---

## 🔍 VERIFICATION CHECKLIST

Use this checklist to verify tools are working correctly:

- [ ] `./Scripts/SaneMaster.rb doctor` - All checks pass
- [ ] `./Scripts/SaneMaster.rb verify` - Tests pass
- [ ] `./Scripts/SaneMaster.rb diagnose --dump` - Logs visible
- [ ] `bundle exec lefthook run pre-commit` - Linting works
- [ ] `xcodegen generate --check` - Project in sync
- [ ] `swiftlint lint --strict` - No file length violations
- [ ] `./Scripts/SaneMaster.rb gen_mock --target Services/Camera` - Mocks generate correctly
- [ ] `./Scripts/SaneMaster.rb gen_test TestExample` - Test template generates

---

## 📝 NOTES

- **Single Source of Truth**: DEVELOPMENT.md is authoritative, but needs line 15 fix
- **Tool Centralization**: All tools should go through SaneMaster.rb (✅ followed)
- **Determinism**: Most processes are deterministic, but file size and xcodegen checks need automation
- **Hallucination Prevention**: SDK verification workflow exists but needs tooling to make it easier

---

**Last Updated**: 2025-12-24
**Status**: ✅ **ALL RECOMMENDATIONS COMPLETE** - All high and low priority items implemented


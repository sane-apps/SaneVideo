# SaneVideo Development Guide (SOP)

> **SINGLE SOURCE OF TRUTH** for all Developers and AI Agents.
>
> **SOP = Standard Operating Procedure = This File (DEVELOPMENT.md)**
>
> When you see "SOP", "use our SOP", or "follow the SOP", this is the document.
>
> **Read this entirely before touching code.**

---

## 🚀 Quick Start for AI Agents

**New to this project? Start here:**

1. **Read this file** (DEVELOPMENT.md) - It's the single source of truth
2. **Check current status**: 
   - Tests are disabled (see section 8)
   - Use `test_suite --quick` instead of running tests
3. **Use SaneMaster.rb**: All tools are in `./Scripts/SaneMaster.rb`
4. **Reference docs**: See section 9 for documentation structure

**Key Commands:**
```bash
./Scripts/SaneMaster.rb setup      # Initial setup
./Scripts/SaneMaster.rb verify     # Build app (tests disabled)
./Scripts/SaneMaster.rb test_suite --quick  # Comprehensive validation
```

**Supplementary Documentation:**
- `TESTING_SUMMARY.md` - Quick testing reference
- `ALTERNATIVE_TESTING.md` - Detailed alternative testing guide
- `CI_TEST_STATUS.md` - CI-specific test status
- `TEST_DISABLED_NOTICE.md` - Local test status

**All other docs are historical/archive - refer to DEVELOPMENT.md first.**

---

## 0. Critical System Context: macOS 26.2 (Tahoe)

- **OS**: macOS 26.2 (Tahoe). APIs differ from older versions.
- **Hardware**: Apple Silicon (M1+) ONLY. No Intel support.
- **Rule**: If unsure about an API, **CHECK THE SDK FIRST** (see SDK verification workflow in Golden Rules), then search the web for context/usage. Do not guess.

---

## 1. The "Golden Rules" (CRITICAL)

1. **USE SaneMaster.rb FIRST**: Use `./Scripts/SaneMaster.rb` for verification, setup, and diagnostics.
2. **VERIFY LOGS ALWAYS**: Run `./Scripts/SaneMaster.rb diagnose --dump` after every build/test to see runtime logs (e.g. `ProjectStore initialized at...`).
3. **FILE CREATION = XCODEGEN**: If you create a new file, run `xcodegen generate` immediately.
4. **MAX FILE SIZE = 500 LINES**: Absolute limit per Swift file. Enforced by automation.
5. **SAFETY FIRST**: Every bug fix **MUST** have a regression test.
6. **SDK IS THE SOURCE OF TRUTH (CRITICAL)**:
   - **NEVER trust web search for API existence or signatures**.
   - **ALWAYS query the SDK directly** before assuming an API exists or is deprecated.
   - The SDK `.swiftinterface` files are the **authoritative source**.
   - **Use tool**: `./Scripts/SaneMaster.rb verify_api <APIName> [Framework]` to verify APIs.
   - See workflow: `.agent/workflows/sdk-api-verification.md`
   - Example: `./Scripts/SaneMaster.rb verify_api faceCaptureQuality Vision`
7. **FIX THE TOOL (Critical Protocol)**
   - **Trigger**: Persistent errors or repetitive manual work.
   - **Action**: STOP. Fix or upgrade the underlying tool (`SaneMaster.rb`).
   - **Constraint**: If you don't get something right twice in a row, check the SDK then the web for help.
8. **WEB SEARCH IS SECONDARY**: Only use web search for understanding *why* or *how* after verifying with SDK.
9. **MISSING TOOL = UPGRADE SANEMASTER**: Do not create separate scripts. Upgrade the central `SaneMaster.rb`.

---

## 2. Quick Start

### The "One-Stop" Script

```bash
# Setup dependencies and environment
./Scripts/SaneMaster.rb setup

# Verify everything (Build + Tests)
./Scripts/SaneMaster.rb verify

# Generate usage assets (e.g. tests)
./Scripts/SaneMaster.rb gen_assets
```

### Manual Generation (If needed)

**NEVER** edit `project.pbxproj` manually.

```bash
xcodegen generate
open SaneVideo.xcodeproj
```

---

## 3. Architecture & Principles

### Core Philosophy

1. **Strict Modularity**: Small, focused files (<500 lines).
2. **Concurrency by Design**: Use `actor` for shared state. Avoid manual locks.
3. **Protocol-Driven**: Define protocols (`CameraServiceProtocol`) before implementation.
4. **Avoid Singletons**: Inject dependencies. Minimize `AppState.shared`.

### System Layers

```text
User Action → AppState → Service → Model Update → UI Refresh
```

1. **UI Layer (SwiftUI)**: Views bind to state. Minimal logic.
2. **Service Layer**: Heavy lifting (AVFoundation, Vision). Actors.
3. **Core Layer**: Models, Extensions, Utilities.

### Directory Structure

```text
SaneVideo/
├── Core/                  # Foundation types
│   ├── Models/           # Domain models (VideoProject, Timeline, VideoClip)
│   ├── Protocols/        # Service protocols for DI
│   ├── Utilities/        # Shared utilities (TimecodeFormatter)
│   ├── DI/               # Dependency injection container
│   ├── Engine/           # Core engines
│   ├── Extensions/       # Swift extensions
│   ├── Performance/      # Performance monitoring
│   ├── Rendering/        # Rendering utilities
│   ├── AppError.swift    # Unified error handling
│   └── AppLogger.swift   # Centralized logging
├── Services/             # Business logic (20+ services)
│   ├── AI/              # AI providers (OpenAI, Gemini, Apple Intelligence)
│   ├── Audio/           # Audio processing, waveforms, voice isolation
│   ├── Camera/          # Camera capture (CameraManager)
│   ├── Captions/        # Caption generation
│   ├── Export/          # Export engine (ExportEngine)
│   ├── Project/         # Persistence (ProjectStore)
│   ├── Recording/       # Recording engine (RecordingEngine)
│   ├── SmartFeatures/   # Magic Fix, smart tools
│   ├── Thumbnails/      # Smart thumbnail generation
│   ├── Timeline/        # Timeline operations
│   └── Vision/          # Vision ML (face tracking, segmentation, saliency)
├── State/               # App state management
│   ├── AppState.swift   # Main app state coordinator
│   ├── ProjectState.swift + extensions  # Project-specific state
│   ├── RecordingState.swift
│   ├── PlaybackState.swift
│   └── CameraState.swift
├── Views/               # SwiftUI views
│   ├── Components/      # Reusable UI components
│   ├── Sheets/          # Modal sheets
│   ├── MainContentView.swift
│   ├── TimelineView.swift
│   └── ...
└── Windows/             # Custom windows (FloatingControls, PiP)
```

### Concurrency Model

- **@MainActor**: AppState, all ObservableObjects, UI updates
- **Background queues**: AVFoundation operations, file I/O
- **Swift Concurrency**: Prefer async/await over completion handlers

### Logging Categories

```swift
AppLogger.camera      // AVCapture operations
AppLogger.recording   // Recording lifecycle
AppLogger.export      // Export operations
AppLogger.timeline    // Timeline edits
AppLogger.project     // Persistence
AppLogger.ui          // UI events
AppLogger.general     // Everything else
```

---

## 4. Style Guide & Best Practices

### Formatting

- **Line Length**: 120 chars max.
- **Indent**: 4 spaces.
- **Linting**: Enforced by `swiftlint`.

### SwiftUI

- use `Trailing Closure` syntax for modifiers (`.background { Color.blue }`).
- Extract complex views into subviews or properties if body > 50 lines.
- Use `@Observable` (Swift 5.9+) for state objects.
- Use `Task { await ... }` instead of `DispatchQueue`.

### Naming

- **Services**: `CameraManager`, `AudioService`.
- **Views**: `VideoPlayerView`, `SettingsButton`.
- **Actions**: `loadVideo()`, `saveProject()`. (Verbs).

### Error Handling

- Use `AppError` enum. Never throw raw `NSError` or strings.
- Handle errors at the call site or propagate explicitly.

---

## 5. Workflows

### Building & Verification (Unified Workflow)

**The Mandate**: You must see the logs every time you build.

#### 1. Quick Verification (Fast, Incremental)

Use this for rapid iteration. **UI tests are optional and skipped by default** - run them manually when ready.

```bash
# Default: Build only (tests disabled due to environment limitations)
# ⚠️ Tests are currently disabled - see TEST_DISABLED_NOTICE.md
./Scripts/SaneMaster.rb verify

# Note: Test execution is currently disabled
# Use alternative testing methods (see "Alternative Testing Methods" section)
./Scripts/SaneMaster.rb verify --ui

# Optional: Full Clean Build (Slow, ~30s)
./Scripts/SaneMaster.rb verify --clean
```

#### 2. Full System Check (Slow, Complete)

Use this before pushing code. **Note**: Tests are currently disabled in both local and CI environments. Use static analysis tools instead (see "Alternative Testing Methods").

```bash
bundle exec fastlane verify_full
```

#### 3. Analyzing Logs

Always diagnostics after a run:

```bash
./Scripts/SaneMaster.rb diagnose --dump
```

*Why?* This ensures you see "ProjectStore initialized at..." and other critical runtime events that Xcode/MCP might swallow.

---

## 6. Troubleshooting

- **Ghost Beeps / No Launch**: Run `xcodegen generate`.
- **"Signal 9" Crash**: Check `SaneVideo.entitlements` for App Sandbox.
- **Phantom Errors**: Run `./Scripts/SaneMaster.rb clean --nuclear`.
- **Permissions Black Screen**: Run `tccutil reset Camera`.
- **Test Execution Disabled**: 
  - **Local**: SwiftUICore linker error (Xcode 16/macOS 26.2 bug) - see `TEST_DISABLED_NOTICE.md`
  - **CI**: Deployment target mismatch (CI runners have macOS 26.0.1, app requires 26.2) - see `CI_TEST_STATUS.md`
  - **Workaround**: Use alternative testing methods (static analysis, API verification, manual testing)
  - **To re-enable**: See `TEST_DISABLED_NOTICE.md` for local, `CI_TEST_STATUS.md` for CI

---

## 7. Available Tools

1. **SaneMaster.rb** (`./Scripts/SaneMaster.rb`): The master controller.
    - `verify`: Build app only (tests automatically skipped when disabled).
    - `verify --clean`: Full clean build (tests skipped).
    - **Note**: Test execution is currently disabled - use alternative testing methods.
    - `doctor`: Health check (environment, assets, permissions, XcodeGen sync).
    - `console`: **Interactive Ruby REPL** (Pry) for debugging scripts.
    - `gen_test <name>`: Generate test files.
    - `gen_mock [options]`: Generate mocks using Mockolo.
    - `verify_api <APIName> [Framework]`: Verify API exists in SDK (prevents hallucinations).
    - `verify_mocks`: Check if mocks are synchronized with protocols.
    - `check_docs`: Verify documentation matches tool capabilities.
    - `check_deprecations`: Scan for deprecated API usage and warnings.
    - `dead_code`: Scan for unused code using Periphery.
    - `test_suite [--quick] [--full] [--ci]`: **Comprehensive validation suite** - Runs all static analysis tools in one command.
      - `--quick`: Fast checks only (build, lint, test references, xcodegen)
      - `--full`: All checks including slow ones (dead code, deprecations)
      - `--ci`: CI-optimized (excludes slow checks, includes build)
2. **Ruby Power Tools** (via `bundle exec`):
    - **Lefthook**: **The Enforcer**. Automates `swiftlint` on commit and `verify` on push.
    - **Fastlane**: Release orchestration & CI/CD.
      - `bundle exec fastlane verify` - Unit tests only (fast)
      - `bundle exec fastlane verify_full` - All tests including UI
      - `bundle exec fastlane coverage` - Generate code coverage report
      - `bundle exec fastlane release` - Full release preparation (includes coverage)
    - **Pry**: `bundle exec pry` for interactive debugging.
    - **RuboCop**: `bundle exec rubocop` for script linting.
    - **Bundler-Audit**: `bundle exec bundle-audit` for security.
3. **XcodeBuildMCP**: Use for granular programmatic builds/tests.

### Test Generation Tool

**Usage:**

```bash
# Generate unit test with Swift Testing framework (default)
./Scripts/SaneMaster.rb gen_test MyFeatureTests --target MyFeature

# Generate UI test with XCTest
./Scripts/SaneMaster.rb gen_test MyUITests --type ui --framework xctest

# Generate async test
./Scripts/SaneMaster.rb gen_test AsyncTests --async
```

**Features:**

- ✅ Generates proper test structure following AAA pattern
- ✅ Includes timeout configuration
- ✅ Adds TestEnvironment helper methods
- ✅ Supports both Swift Testing and XCTest frameworks
- ✅ Handles async/await patterns
- ✅ Follows project conventions

**See:** `TESTING_BEST_PRACTICES.md` for comprehensive testing guidelines.

---

## 8. Testing Strategy (Current Status)

> **⚠️ IMPORTANT**: Automated test execution is currently **disabled** due to environmental limitations:
> - **Local**: Tests disabled due to SwiftUICore linker error (Xcode 16/macOS 26.2 bug)
> - **CI**: Tests disabled due to deployment target mismatch (CI runners have macOS 26.0.1, app requires 26.2)
> 
> **What Still Works**:
> - ✅ Build verification (`./Scripts/SaneMaster.rb verify` builds app only)
> - ✅ Static analysis tools (see "Alternative Testing Methods" below)
> - ✅ Test code is preserved and will be re-enabled when environment supports it
>
> **See**: `TEST_DISABLED_NOTICE.md` and `CI_TEST_STATUS.md` for details.

### Tier 1: Unit Tests (Fast, <1s) - ⚠️ Currently Disabled

- **Target**: `SaneVideoTests`
- **Scope**: Isolated logic, regex parsing, state machines, math algorithms.
- **Data**: Mocked services, small buffers. **NO** file I/O or app launching.
- **Goal**: Verify logic instantly.

### Tier 2: Integration/UI Tests (Real-World, 10s-60s) - ⚠️ Currently Disabled

- **Target**: `SaneVideoUITests`
- **Scope**: End-to-end user flows, AVFoundation pipeline, CoreML execution.
- **Data**: Real assets (`Tests/Assets/test_video.mp4` or `test_silence.mp4`).
- **Goal**: Verify system stability and functional output.

### Tier 3: Performance & Robustness

- **Objective**: Prevent regressions in export speed and memory usage.
- **Location**: `SaneVideoUITests/SaneEditorFeatureTests.swift` -> `testExportPerformance`
- **Metrics**: Uses `XCTClockMetric` and `XCTMemoryMetric`.
- **Large Assets**: All Timeline UIs MUST use `LazyHStack` or equivalent JIT loading to support 10h+ videos without OOM.
- **Command**: `xcodebuild test ... -only-testing:SaneVideoUITests/SaneEditorFeatureTests/testExportPerformance`
- **Best Practice**: Run before releases. Inspect memory deltas to catch leaks.

### Alternative Testing Methods (Available Now)

Since automated test execution is disabled, use these tools for code validation:

1. **Static Analysis**:
   ```bash
   ./Scripts/SaneMaster.rb validate_test_references  # Verify UI test references match code
   ./Scripts/SaneMaster.rb check_deprecations         # Find deprecated API usage
   ./Scripts/SaneMaster.rb dead_code                  # Find unused code
   ./Scripts/SaneMaster.rb lint                       # Code style and quality
   ```

2. **API Verification**:
   ```bash
   ./Scripts/SaneMaster.rb verify_api <APIName> [Framework]  # Verify APIs exist in SDK
   ```

3. **Build Verification**:
   ```bash
   ./Scripts/SaneMaster.rb verify  # Builds app (tests skipped automatically)
   ```

4. **Manual Testing**: Run the app and test features manually until automated tests are re-enabled.

### Regression Testing (When Tests Re-enabled)

Regression tests are critical for preventing the reintroduction of fixed bugs.

- **Location**: `SaneVideoTests/Regression/`
- **Organization**: Tests are grouped by component (e.g., `RecordingRegressionTests.swift`, `PiPRegressionTests.swift`).
- **When to Add**: Every time a bug is fixed, adding a corresponding regression test is MANDATORY (Golden Rule #5).
- **What to Test**:
    1. **Bug Fix Verification**: Explicitly reproduce the failure mode and verify the fix.
    2. **API Deprecation Checks**: Ensure no deprecated APIs are used (`APIDeprecationTests.swift`).
    3. **Edge Cases**: Test specific scenarios that caused issues previously.
- **Naming**: Use descriptive names referencing the bug (e.g., `testSourceSwitchTimestampGap`).
- **Separation**: Do NOT mix regression tests with feature tests. Keep them in the `Regression/` directory.

### Code Coverage

- **Tool**: xcov (Fastlane plugin)
- **Generate Report**: `bundle exec fastlane coverage`
- **Report Location**: `fastlane/coverage/index.html`
- **Integration**: Automatically included in `bundle exec fastlane release`
- **Configuration**: Enabled in `project.yml` (`ENABLE_CODE_COVERAGE: YES`)
- **Best Practice**: Review coverage reports before releases to identify untested code paths

### Best Practices

- **Expectations over Polling**: Use `expectation(for: predicate, evaluatedWith: object)` instead of `while` loops with `sleep`.
- **Assets**: Use `SaneMaster.rb gen_assets` to create lightweight test media. Use `TestEnvironment` to load heavy media only when necessary.

---

## 9. Documentation Structure

### Primary Documentation (Single Source of Truth)

- **This File (DEVELOPMENT.md)**: Complete SOP, architecture, workflows, style guide
- **README.md**: User-facing features, quick start, keyboard shortcuts
- **AI_AGENT_QUICK_START.md**: Quick reference for AI agents (points to this file)

### Reference Documentation

**Testing (Current Status)**:
- **TESTING_SUMMARY.md**: Quick reference for testing status and alternative methods
- **ALTERNATIVE_TESTING.md**: Detailed guide on alternative testing tools
- **TEST_DISABLED_NOTICE.md**: Local test status and re-enable instructions
- **CI_TEST_STATUS.md**: CI-specific test status and limitations
- **TEST_SUITE_GUIDE.md**: Comprehensive guide for `test_suite` command

**Tools & Research**:
- **OPEN_SOURCE_TOOLS_FINAL.md**: Open source tools research findings
- **TOOLS_AUDIT.md**: Tools audit and recommendations

**Architecture** (if exists):
- **ON_DEVICE_ARCHITECTURE.md**: Details on 100% on-device processing architecture
- **VISUAL_TESTS_SETUP.md**: UI testing setup and permission automation

### Historical/Archive Documentation

The following files are historical records and should NOT be used as primary sources:

- `COMPLETED_IMPROVEMENTS.md` - Completed work log
- `TOOLS_SUMMARY.md` - Superseded by INSTALLED_TOOLS.md
- `TOOLS_AND_IMPROVEMENTS.md` - Superseded by INSTALLED_TOOLS.md
- `TOOLS_RECOMMENDATIONS.md` - Recommendations (some implemented)
- `PERFORMANCE_AUDIT.md` - Audit results (issues addressed)
- `*_COMPLETE.md` files - Historical progress logs
- `UI_UX_IMPROVEMENTS.md` - Historical UI work
- `UI_REFACTOR_PROGRESS.md` - Historical refactor log

**Rule**: When in doubt, refer to DEVELOPMENT.md. If information is missing, add it here rather than creating new files.

---

## 10. For AI Agents

### First Steps

1. **Read this entire file (DEVELOPMENT.md)** - It's the single source of truth
2. **Check AI_AGENT_QUICK_START.md** - Quick reference (but this file is authoritative)
3. **Use SaneMaster.rb** - Don't run raw xcodebuild commands
4. **Always dump logs** - Critical for debugging

### Documentation Priority

1. **DEVELOPMENT.md** - Always check here first
2. **README.md** - For user-facing features
3. **Reference docs** - Only when needed for specific topics
4. **Historical docs** - For context only, not as source of truth

### When Adding Documentation

- **Add to DEVELOPMENT.md** if it's a rule, workflow, or architecture detail
- **Add to README.md** if it's user-facing
- **Create reference doc** only if it's a large, specialized topic (like ON_DEVICE_ARCHITECTURE.md)
- **Don't create** new documentation files for small updates

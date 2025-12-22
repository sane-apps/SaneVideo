# SaneVideo Development Guide (SOP)

> **SINGLE SOURCE OF TRUTH** for all Developers and AI Agents.
> Read this entirely before touching code.

## 0. Critical System Context: macOS 26.2 (Tahoe)

- **OS**: macOS 26.2 (Tahoe). APIs differ from older versions.
- **Hardware**: Apple Silicon (M1+) ONLY. No Intel support.
- **Rule**: If unsure about an API, **SEARCH THE WEB**. Do not guess.

---

## 1. The "Golden Rules" (CRITICAL)

1. **USE SaneMaster.rb FIRST**: Use `./Scripts/SaneMaster.rb` for verification, setup, and diagnostics.
2. **VERIFY LOGS ALWAYS**: Run `./Scripts/SaneMaster.rb diagnose --dump` after every build/test to see runtime logs (e.g. `ProjectStore initialized at...`).
3. **FILE CREATION = XCODEGEN**: If you create a new file, run `xcodegen generate` immediately.
3. **MAX FILE SIZE = 500 LINES**: Absolute limit per Swift file. Enforced by automation.
4. **SAFETY FIRST**: Every bug fix **MUST** have a regression test.
5. **NO HALLUCINATIONS**: Verify APIs via web search.
6. **FIX THE TOOL (Critical Protocol)**
   - **Trigger**: Persistent errors or repetitive manual work.
   - **Action**: STOP. Fix or upgrade the underlying tool (`SaneMaster.rb`).
   - **Constraint**: If you don't get something right twice in a row, check the web for help.
7. **WEB SEARCH IS MANDATORY**: Search authoritative docs when stuck.
8. **MISSING TOOL = UPGRADE SANEMASTER**: Do not create separate scripts. Upgrade the central `SaneMaster.rb`.

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

#### 1. Build, Test, & Dump Logs (One Step)

Use the Agent workflow or run manually:

```bash
# 1. Build and Run Tests to generate logs
mcp_XcodeBuildMCP_test_macos({ "scheme": "SaneVideo", "derivedDataPath": "/Users/sj/SaneVideo/.derivedData" })

# 2. REQUIRED: Dump the full log to console
./Scripts/SaneMaster.rb diagnose --dump
```

*Why?* This ensures you see "ProjectStore initialized at..." and other critical runtime events that Xcode/MCP might swallow.

#### 2. Manual UI Testing

1. Run `./Scripts/SaneMaster.rb gen_assets` to ensure test media exists.
2. Run `xcodebuild test -scheme SaneVideo ...`
3. Run `./Scripts/SaneMaster.rb diagnose --dump` to check the result.

---

## 6. Troubleshooting

- **Ghost Beeps / No Launch**: Run `xcodegen generate`.
- **"Signal 9" Crash**: Check `SaneVideo.entitlements` for App Sandbox.
- **Phantom Errors**: Run `./Scripts/SaneMaster.rb clean --nuclear`.
- **Permissions Black Screen**: Run `tccutil reset Camera`.

---

## 7. Available Tools

1. **SaneMaster.rb**: The master controller.
   - Includes **Permission Monitor** ("God Mode"): Automatically clicks "Allow" on TCC dialogs during tests using AppleScript.
2. **XcodeBuildMCP**: Use for granular programmatic builds/tests.
3. **Fastlane**: For CI/CD (`fastlane verify_full`).

---

## 8. Testing Strategy (Two-Tier)

We balance speed and robustness using two tiers of tests. **Use the right tool for the job.**

### Tier 1: Unit Tests (Fast, <1s)

- **Target**: `SaneVideoTests`
- **Scope**: Isolated logic, regex parsing, state machines, math algorithms.
- **Data**: Mocked services, small buffers. **NO** file I/O or app launching.
- **Goal**: Verify logic instantly.

### Tier 2: Integration/UI Tests (Real-World, 10s-60s)

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

### Best Practices

- **Expectations over Polling**: Use `expectation(for: predicate, evaluatedWith: object)` instead of `while` loops with `sleep`.
- **Assets**: Use `SaneMaster.rb gen_assets` to create lightweight test media. Use `TestEnvironment` to load heavy media only when necessary.

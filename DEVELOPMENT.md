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

1. **Bootstrap runs automatically** - The `.claude/settings.json` SessionStart hook runs `./Scripts/SaneMaster.rb bootstrap` when you open this project
2. **Read the Golden Rules** (Section 1) - Especially Tier 1 rules (#1-3) which prevent hallucinations
3. **Know the Self-Rating requirement** - After every change, rate yourself 1-10 on SOP adherence (see Section 1)
4. **Use SaneMaster.rb**: All tools are in `./Scripts/SaneMaster.rb` — never use raw `xcodebuild`
5. **Tests are working**: Unit tests run with `verify`, UI tests with `verify --ui`

**Your first action when user says "check our SOP" or "use our SOP":**
```bash
./Scripts/SaneMaster.rb bootstrap  # Verify environment (may already have run)
./Scripts/SaneMaster.rb verify     # Build + unit tests
```

**Key Commands:**

```bash
./Scripts/SaneMaster.rb bootstrap  # Environment check + auto-update (runs on session start)
./Scripts/SaneMaster.rb verify     # Build + unit tests (fast, ~30s)
./Scripts/SaneMaster.rb verify --ui  # Build + unit + UI tests (~60s)
./Scripts/SaneMaster.rb test_suite --quick  # Comprehensive validation
```

**SOP Loop Commands (Two-Fix Rule Enforcement):**

```bash
./Scripts/SaneMaster.rb verify_gate       # Run verify with failure tracking (--json for structured output)
./Scripts/SaneMaster.rb sop_loop <prompt> # Start SOP-compliant task loop with auto-verification
./Scripts/SaneMaster.rb reset_escalation  # Clear escalation state after investigation
```

The SOP loop enforces the **Two-Fix Rule**: After 2 consecutive `verify` failures, you MUST stop guessing and investigate:
1. `./Scripts/SaneMaster.rb verify_api <API>` - Verify API exists in SDK
2. Check docs with `apple-docs` or `context7` MCP servers
3. Only then run `reset_escalation` and attempt another fix

Task complexity levels for `sop_loop`:
- `--simple`: 2 iterations (bug fixes, small changes)
- `--moderate`: 4 iterations (features, refactoring) [default]
- `--complex`: 10 iterations (large features, architecture)

**SessionStart Hook (How Auto-Bootstrap Works):**

The `.claude/settings.json` file contains:
```json
"hooks": {
  "SessionStart": [{ "command": "./Scripts/SaneMaster.rb bootstrap" }]
}
```

This runs automatically when you open the project. If bootstrap fails:
1. Check the error message
2. Run `./Scripts/SaneMaster.rb doctor` for diagnostics
3. See Section 6 (Troubleshooting)

**Bootstrap Features:**
- Auto-updates Ruby, bundle, Homebrew tools
- Verifies Claude plugins & MCP servers
- **Auto-fixes common issues**: Kills stuck xcodebuild/xctest processes, clears DerivedData if >5GB
- Creates rollback snapshots before changes
- Logs all operations to `~/.sanemaster/logs/`
- Use `--check-only` to report without changes
- Use `--rollback` to restore previous configuration
- Use `--no-fix` to skip auto-fixing (report only)

**Supplementary Documentation:**

- `TEST_CREATION_WORKFLOW.md` - **Test creation workflow** (trigger: "enter test creation workflow")
- `TEST_COVERAGE_ANALYSIS.md` - Coverage analysis and gaps

**All other docs are historical/archive - refer to DEVELOPMENT.md first.**

---

## ⚠️ SOP Internalization Protocol

**The #1 failure mode: skimming this SOP instead of internalizing it.**

**Before coding, explicitly map rules to your task:**
```
"For this task:
- Rule #1 applies because [reason]
- Rule #7 applies because [reason]"
```

**While working, actively ask:** "Which rule applies here?"
- Using an Apple API? → Rule #1 (SDK verification)
- Failed twice? → Rule #2 (stop guessing, investigate)
- New file? → xcodegen generate

**The key insight:** The difference between 8/10 and 5/10 sessions is NOT knowing the rules—it's **structuring work around which rules apply to each task**.

Skimming = "I know there are rules" → Internalizing = "Rule #3 applies HERE"

---

## 0. Critical System Context: macOS 26.2 (Tahoe)

- **OS**: macOS 26.2 (Tahoe). APIs differ from older versions.
- **Hardware**: Apple Silicon (M1+) ONLY. No Intel support.
- **Ruby**: Homebrew Ruby 3.4+ required. System Ruby 2.6 is deprecated. A `.ruby-version` file is provided for version managers.
- **Rule**: If unsure about an API, **CHECK THE SDK FIRST** (see SDK verification workflow in Golden Rules), then search the web for context/usage. Do not guess.

---

## 1. The 13 Golden Rules (CRITICAL)

Rules are ordered by priority. **Tier 1 rules prevent disasters** — read them first.

### Tier 1: Anti-Hallucination (READ FIRST)

1. **SDK IS THE SOURCE OF TRUTH (CRITICAL)**:
   - **NEVER trust web search for API existence or signatures**.
   - **ALWAYS query the SDK directly** before assuming an API exists or is deprecated.
   - The SDK `.swiftinterface` files are the **authoritative source**.
   - **Verification flow**:
     1. `./Scripts/SaneMaster.rb verify_api <APIName> [Framework]` — Verify API exists in SDK
     2. `apple-docs` MCP server — Get usage examples, related APIs, WWDC context
   - Example: `./Scripts/SaneMaster.rb verify_api faceCaptureQuality Vision`

2. **TWO-FIX RULE (CRITICAL)**: If you fail twice in a row, **STOP GUESSING**.
   - Don't try a third approach — you're likely missing information
   - Go back to Rule #1: verify the API exists in SDK
   - Check documentation or ask user
   - Why: Third-attempt guessing wastes tokens and often makes things worse

3. **WEB SEARCH IS SECONDARY**: Only use web search for understanding *why* or *how* after verifying API exists with SDK. Never use web search to confirm if an API exists.

### Tier 2: Core Workflow (Do these every session)

4. **USE SaneMaster.rb (NOT raw xcodebuild)**: Use `./Scripts/SaneMaster.rb` for verification, setup, and diagnostics. Never use raw `xcodebuild` commands.

5. **AUTOMATIC BUILD & LAUNCH WITH LOGGING (CRITICAL)**: After making code changes, you **MUST**:
   - Build the app: `./Scripts/SaneMaster.rb verify`
   - Kill any running instances: `killall -9 SaneVideo`
   - Launch with live logging: `./Scripts/SaneMaster.rb launch` followed by `./Scripts/SaneMaster.rb logs --follow`
   - **Rationale**: Old instances can hold stale state, and live logs are essential for debugging

6. **VERIFY LOGS ALWAYS**: Run `./Scripts/SaneMaster.rb diagnose --dump` after every build/test to see runtime logs (e.g. `ProjectStore initialized at...`).

### Tier 3: Code Quality (Maintain standards)

7. **SAFETY FIRST**: Every bug fix **MUST** have a regression test. Create tests as you go using `./Scripts/SaneMaster.rb gen_test`.
   - **Test Quality**: Tests must verify **actual behavior**, not just that code doesn't crash.
   - **NEVER use placeholders**: `#expect(true)` or `#expect(true, "message")` verify nothing and are forbidden.
   - **NEVER use tautologies**: `#expect(a == true || a == false)` always passes and provides zero value.
   - **Verify specific outcomes**: Test return values, state changes, error types, not just "does not crash".

8. **BUG TRACKING (CRITICAL)**: Document ALL bugs in `BUG_TRACKING.md` immediately when discovered.
   - **During session**: Use TodoWrite to track active work (ephemeral)
   - **After session**: Update BUG_TRACKING.md for permanent record
   - Include: Status (🔴 OPEN → 🟡 IN PROGRESS → ✅ FIXED), Screenshot filename, Symptom, File(s), Root cause
   - **Flow**: User reports bug → TodoWrite entry → Fix → Mark complete → Update BUG_TRACKING.md

9. **FILE CREATION = XCODEGEN**: If you create a new file, run `xcodegen generate` immediately.

10. **FILE SIZE LIMITS**: Soft limit **500 lines** (warning), hard limit **800 lines** (error).
    - **Split by responsibility, not by line count.** A well-constructed 650-line file is preferable to two files that break logical cohesion.
    - **Good splits**: Protocol conformances, feature domains, lifecycle concerns.
    - **Bad splits**: Arbitrary cuts just to hit a number.

### Tier 4: Meta/System (System improvement)

11. **FIX THE TOOL, NOT THE SYMPTOM**: If you encounter persistent errors or repetitive manual work, STOP. Fix or upgrade `SaneMaster.rb` instead of working around the issue.

12. **MISSING TOOL = UPGRADE SANEMASTER**: Do not create separate scripts. Add functionality to `SaneMaster.rb`.

13. **ALWAYS VERIFY CURRENT STATE**: Do NOT rely on training data for project specifics (window names, view hierarchies, API signatures). Use `grep`/`find` to discover the actual codebase state. The codebase changes; training data is stale.

---

### Self-Rating After Changes (MANDATORY)

After completing ANY code change, fix, or task, you **MUST** rate yourself 1-10 on SOP adherence:

```
**Self-rating: X/10**
- ✅ What you did well (SOP compliance)
- ❌ What you missed or could improve
```

**Rating Guide:**
| Score | Meaning | Example |
|-------|---------|---------|
| 9-10 | Flawless SOP execution | Used SaneMaster, ran verify, killed processes, checked logs, added regression test |
| 7-8 | Good, minor misses | Did most things right but forgot to check logs |
| 5-6 | Acceptable, notable gaps | Built with xcodebuild directly (should use SaneMaster), skipped logs |
| 3-4 | Poor, multiple violations | Guessed at APIs without SDK verification, no tests |
| 1-2 | Failed to follow SOP | Ignored most rules, made random changes |

**Key SOP items to self-check:**
- [ ] Used SaneMaster.rb (not raw xcodebuild)?
- [ ] Ran verify after code changes?
- [ ] Killed old instances before launch?
- [ ] Checked logs after changes?
- [ ] Added regression test for bug fixes?
- [ ] Used SDK verification before assuming API exists (Rule #1)?
- [ ] Followed Two-Fix Rule (stopped guessing after 2 failures)?
- [ ] Documented bugs appropriately?

### Comprehensive Reviews (Use Subagents)

When the user requests a **full app review**, **codebase audit**, or **comprehensive check**, use **parallel subagents** to maximize coverage:

```bash
# Launch these in parallel (all at once, not sequentially):
Task(subagent_type=Explore): "Analyze file size violations and recommend splits"
Task(subagent_type=Explore): "Analyze test coverage gaps"
Task(subagent_type=Explore): "Check dead code and deprecations"
Task(subagent_type=Explore): "Review architecture patterns"
Task(subagent_type=Explore): "Check security and crash patterns"
```

**Why subagents:**
- Each agent explores deeply in its domain (doesn't miss things)
- Parallel execution = faster results
- User doesn't have to catch things you missed

**Expected outputs:**
- File size agent: Specific split recommendations with line numbers
- Coverage agent: Missing test areas ranked by risk/priority
- Dead code agent: Safe-to-delete vs false positives
- Architecture agent: Race conditions, anti-patterns, DI issues
- Security agent: Crash patterns, memory leaks, force unwraps

**Self-Rating impact:** If user has to catch issues you missed → lower rating.

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

1. **Strict Modularity**: Small, focused files (target <500 lines, max 800 lines).
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
│   ├── AI/              # AI providers (Apple Intelligence)
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
AppLogger.uiLog       // UI events
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
# Default: Build + run unit tests (fast, ~1s)
./Scripts/SaneMaster.rb verify

# Include functional UI tests (excludes visual tests - manual only)
./Scripts/SaneMaster.rb verify --ui

# Optional: Full Clean Build (Slow, ~30s)
./Scripts/SaneMaster.rb verify --clean
```

#### 2. Full System Check (Slow, Complete)

Use this before pushing code. **Note**: Visual tests are excluded from automated runs (manual testing only).

```bash
bundle exec fastlane verify_full
```

#### 3. Analyzing Logs

Always diagnostics after a run:

```bash
./Scripts/SaneMaster.rb diagnose --dump
```

*Why?* This ensures you see "ProjectStore initialized at..." and other critical runtime events that Xcode/MCP might swallow.

#### 4. Test Mode vs Verify: When to Use Which

| Scenario | Command | What It Does |
|----------|---------|--------------|
| After code changes | `./Scripts/SaneMaster.rb verify` | Build + run unit tests (automated, ~30s) |
| Before committing | `./Scripts/SaneMaster.rb verify --ui` | Build + unit + UI tests (automated, ~60s) |
| User testing live | See "Test Mode" below | Kill → Build → Launch → Stream logs |
| Debugging crash | See Section 6 | Crash analysis workflow |

**Key distinction:**
- **`verify`** = Automated, no user interaction, confirms code compiles and tests pass
- **Test Mode** = Interactive, user provides feedback, you watch logs in real-time

**Test Mode workflow (when user says "test mode" or you need live debugging):**
```bash
./Scripts/SaneMaster.rb test_mode   # Preferred: runs all steps below automatically
# Or manually: killall -9 SaneVideo && ./Scripts/SaneMaster.rb verify && ./Scripts/SaneMaster.rb launch
# Then: ./Scripts/SaneMaster.rb logs --follow   # Stream logs
```

Monitor these resources while user tests:
- **Debug log**: `~/Movies/SaneVideo/SaneVideo_Debug.log`
- **Screenshots**: `Screenshots/` in project root
- **Crash reports**: `~/Library/Logs/DiagnosticReports/SaneVideo-*.ips`

---

## 6. Troubleshooting

- **Ghost Beeps / No Launch**: Run `xcodegen generate`.
- **"Signal 9" Crash**: Check `SaneVideo.entitlements` for App Sandbox.
- **Phantom Errors**: Run `./Scripts/SaneMaster.rb clean --nuclear`.
- **Permissions Black Screen**: Run `tccutil reset Camera`.
- **Test Execution**: Tests are working! Unit tests and functional UI tests run automatically. Visual tests are excluded (manual testing only).

### Crash/Log Analysis SOP (MANDATORY for Debugging)

**When to use this**: After ANY crash, freeze, or unexpected behavior. Run this **before** attempting fixes.

#### Quick Decision Tree

```
App problem?
    │
    ├─ App still running but misbehaving?
    │   └─ Check logs: ./Scripts/SaneMaster.rb logs --follow
    │
    ├─ App crashed/exited?
    │   └─ Check crash reports: ls ~/Library/Logs/DiagnosticReports/ | grep -i sane
    │       │
    │       ├─ Crash files exist? → Analyze with Step 2 below
    │       └─ No crash files? → Check application logs (Step 3)
    │
    └─ App frozen/hanging?
        └─ Kill it: killall -9 SaneVideo
            └─ Then check logs and relaunch
```

#### Step 0: The "Nuclear" Relaunch (CRITICAL)

If the app is malfunctioning or crashing, do NOT just re-launch it. Old zombie processes can pollute logs and hold resources.

1. **KILL**: `killall -9 SaneVideo`
2. **LAUNCH**: `./Scripts/SaneMaster.rb launch`
3. **LOGS**: Immediately run `log show --predicate 'process == "SaneVideo"' --last 1m` or stream with `log stream`.

#### Step 1: Collect Crash Reports

```bash
# List all SaneVideo crash reports
ls -la ~/Library/Logs/DiagnosticReports/ | grep -i sane

# Analyze crash type distribution (PATTERN DETECTION)
for f in ~/Library/Logs/DiagnosticReports/SaneVideo-*.ips; do
  grep -o '"type":"[^"]*"' "$f" | head -1
done | sort | uniq -c | sort -rn

# Get crash signatures (top 4 frames) to identify patterns
for f in ~/Library/Logs/DiagnosticReports/SaneVideo-*.ips; do
  python3 -c "
import json
import sys

lines = open('$f').read().split('\n')
for i, line in enumerate(lines):
    if line.strip() == '{':
        json_start = i
        break
try:
    data = json.loads('\n'.join(lines[json_start:]))
    for t in data.get('threads', []):
        if t.get('triggered'):
            sig = ' -> '.join([f.get('symbol', '?')[:40] for f in t.get('frames', [])[:4]])
            print(sig)
            break
except: pass
" 2>/dev/null
done | sort | uniq -c | sort -rn | head -10
```

#### Step 2: Analyze Specific Crash

```bash
# Detailed analysis of most recent crash
CRASH=$(ls -t ~/Library/Logs/DiagnosticReports/SaneVideo-*.ips | head -1)
python3 -c "
import json
lines = open('$CRASH').read().split('\n')
for i, line in enumerate(lines):
    if line.strip() == '{':
        json_start = i
        break
data = json.loads('\n'.join(lines[json_start:]))
print('Exception:', data.get('exception', {}))
print()
for t in data.get('threads', []):
    if t.get('triggered'):
        print('Queue:', t.get('queue', 'unknown'))
        for i, f in enumerate(t.get('frames', [])[:15]):
            sym = f.get('symbol', '?')
            src = f.get('sourceFile', '')
            line = f.get('sourceLine', '')
            print(f'  {i}: {sym}')
            if src: print(f'      {src}:{line}')
        break
"
```

#### Step 3: Check Application Logs

**File-based logs** (recommended - always available):

```bash
# Show today's logs
./Scripts/SaneMaster.rb logs

# Show last 100 lines
./Scripts/SaneMaster.rb logs --tail 100

# Follow logs live (like tail -f)
./Scripts/SaneMaster.rb logs --follow
```

Log files are stored at: `~/Movies/SaneVideo/SaneVideo_Debug.log` (overwrites on each app launch for easy debugging)

**System unified logs** (only available when streaming):

```bash
# Stream live (only works while app is running)
log stream --predicate 'subsystem == "com.sanevideo.SaneVideo"' --level debug

# NOTE: macOS filters debug/info logs by default - they're NOT persisted to disk!
# Use file-based logging above for reliable log capture.

# IMPORTANT: Bundle IDs vs. Logger Subsystem
# - App bundle ID:      com.sanevideo.app (used for tccutil, signing, permissions)
# - Logger subsystem:   com.sanevideo.SaneVideo (used for log stream predicate)
# These are intentionally different!
```

#### Common Crash Patterns & Fixes

| Pattern | Crash Signature | Root Cause | Fix |
|---------|-----------------|------------|-----|
| **Actor Isolation** | `MainActor.assumeIsolated → dispatch_assert_queue_fail` | Calling MainActor code from background thread | Remove `MainActor.assumeIsolated` from `deinit`, use `nonisolated(unsafe)` for Tasks |
| **Object Deallocated** | `objc_opt_class → swift_getObjectType → isMainExecutor → SIGSEGV at 0x1e` | Timer/Publisher accessing deallocated view | Use `TimelineView` instead of `Timer.publish()`, add `isActive` guards |
| **Test Cleanup** | `objc_release → XCTMemoryChecker` | Test objects not properly cleaned up | Ensure async tasks complete before test ends |
| **Race Condition** | `objc_release → SIGSEGV` at random addresses | Concurrent access to non-thread-safe property | Use `nonisolated(unsafe)` with direct initialization (not lazy) |
| **Nested Tasks** | Freeze at `_isSameExecutor` | Excessive actor hopping creating deadlock | Remove nested `Task { @MainActor in Task { @OtherActor in } }` patterns |

#### Key Warning Signs

- **Address 0x0-0x1000**: NULL pointer dereference (object deallocated)
- **faultingThread: 0**: Main thread crash (UI/state issue)
- **faultingThread: N > 0**: Background thread crash (concurrency issue)
- **EXC_BREAKPOINT (SIGTRAP)**: Swift assertion failed or `assumeIsolated` violation
- **EXC_BAD_ACCESS (SIGSEGV)**: Memory corruption or use-after-free

---

## 7. Available Tools

1. **SaneMaster.rb** (`./Scripts/SaneMaster.rb`): The master controller.
    - `bootstrap`: **Auto-runs on session start.** Full environment bootstrap with auto-update, rollback support, and session logging.
    - `verify`: Build app + run unit tests (default).
    - `verify --clean`: Full clean build + run unit tests.
    - `verify --ui`: Build + run unit tests + functional UI tests (excludes visual tests).
    - `doctor`: Health check (environment, assets, permissions, XcodeGen sync).
    - `console`: **Interactive Ruby REPL** (Pry) for debugging scripts. Requires: `bundle exec ./Scripts/SaneMaster.rb console`
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
4. **Claude Code Plugins** (install via `/plugin install`):
    - **swift-lsp@claude-plugins-official**: ✅ Enabled - Provides Swift code intelligence (completion, go-to-definition, diagnostics)
    - **code-review@claude-plugins-official**: ✅ Enabled - Automated PR review with 4 parallel agents
    - **security-guidance@claude-plugins-official**: ✅ Enabled - Security vulnerability alerts during editing
    - **ralph-wiggum@claude-plugins-official**: ✅ Enabled - **SOP Enforcement Loop** - Prevents task completion until verification criteria are met (see below)
5. **MCP Servers** (configured in `.mcp.json`):
    - **Note**: Ensure `enableAllProjectMcpServers: true` is set in `.claude/settings.local.json` and no restrictive `enabledMcpjsonServers` array exists.
    - **apple-docs**: ✅ Enabled - Apple Developer Documentation & WWDC transcripts (1,260+ sessions, 2012-2025). Use for API examples, related APIs, and understanding "why" behind APIs.
    - **github**: ✅ Enabled - GitHub API integration for issues, PRs, repos, and code search. (Official MCP)
    - **memory**: ✅ Enabled - Persistent knowledge graph for cross-session context. (Official MCP)
    - **context7**: ✅ Enabled - Real-time, version-specific library documentation. Prevents hallucinated APIs by fetching current docs from source repos.
    - **XcodeBuildMCP**: ✅ Enabled - Programmatic Xcode builds, test runs, and code signing. Use for CI/CD integration.

### When to Use Which Tool (Decision Matrix)

| Situation | Tool to Use | Why |
|-----------|-------------|-----|
| **Need API signature or existence** | `./Scripts/SaneMaster.rb verify_api` | SDK is source of truth (Rule #6) |
| **Need API usage examples or WWDC context** | `apple-docs` MCP | Rich examples, related APIs, historical context |
| **Need up-to-date library docs (WhisperKit, Vapor, etc.)** | `context7` MCP | Fetches real-time docs from source repos |
| **Build/test the project** | `./Scripts/SaneMaster.rb verify` | Always use SaneMaster (Rule #1) |
| **Programmatic builds (CI/CD)** | `XcodeBuildMCP` | Granular control, JSON output, automation |
| **Generate mock classes** | `./Scripts/SaneMaster.rb gen_mock` (Mockolo) | Fast protocol→mock generation |
| **Generate test templates** | `./Scripts/SaneMaster.rb gen_test` | Creates structured unit/UI tests |
| **iOS companion app testing** | XcodeBuildMCP + manual | Enable additional tools when mobile dev begins |
| **GitHub issues/PRs** | `github` MCP | Create issues, review PRs, search code |
| **Remember context across sessions** | `memory` MCP | Persistent knowledge graph |
| **Code intelligence (completions, go-to-def)** | `swift-lsp` plugin | IDE-like Swift support in Claude Code |

### Future: iOS/iPadOS Companion Apps

> **Current Focus**: macOS app until rock solid. iOS/iPad work comes later.

When developing the iPhone/iPad companion apps:
- **XcodeBuildMCP** can target iOS simulators and devices
- Shared code should live in a Swift Package for cross-platform use
- Use `apple-docs` for platform-specific API differences (UIKit vs AppKit)

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

**See:** `TEST_CREATION_WORKFLOW.md` for test creation workflow and best practices.

### Ralph Wiggum: SOP Enforcement Loop

**Purpose**: Forces Claude to complete ALL SOP requirements before claiming a task is done.

**How it works**:
1. You run `/ralph-loop` with a prompt containing SOP requirements
2. Claude works on the task
3. When Claude tries to exit, a Stop hook intercepts and feeds the prompt back
4. Claude sees previous work and iterates until completion criteria are met
5. Loop exits when `<promise>COMPLETE</promise>` appears or max iterations hit

**Usage for bug fixes**:

```bash
/ralph-loop "Fix: [describe bug]

SOP Requirements (verify before completing):
1. ./Scripts/SaneMaster.rb verify passes
2. killall -9 SaneVideo && ./Scripts/SaneMaster.rb launch
3. ./Scripts/SaneMaster.rb logs --follow (check for errors)
4. Regression test added in SaneVideoTests/Regression/
5. Self-rating 1-10 provided

Output <promise>SOP-COMPLETE</promise> ONLY when ALL verified." --completion-promise "SOP-COMPLETE" --max-iterations 10
```

**Usage for features**:

```bash
/ralph-loop "Implement: [describe feature]

Requirements: [list requirements]

SOP: verify passes, logs checked, self-rating provided.

<promise>FEATURE-DONE</promise>" --completion-promise "FEATURE-DONE" --max-iterations 15
```

**Commands**:
- `/ralph-loop "<prompt>" --completion-promise "<text>" --max-iterations N` - Start loop
- `/cancel-ralph` - Cancel active loop

**When to use**:
- Complex bug fixes requiring multiple verification steps
- Feature implementations with many requirements
- Any task where Claude tends to skip SOP steps

**Auto-injection**: SOP context is automatically injected at session start via `.claude/SOP_CONTEXT.md`.

---

## 8. Testing Strategy (Current Status)

> **✅ Tests are now working!** Apple fixed the SwiftUICore linker error that was preventing test execution.
>
> **Current Status**:
>
> - ✅ **Unit Tests**: Working (`SaneVideoTests`)
> - ✅ **Code-based UI Tests**: Working (functional tests in `SaneVideoUITests`)
> - ⚠️ **Visual Tests**: Skipped by default (manual testing only - see below)
>
> **Visual Tests** (excluded from automated runs):
> - `SaneSmartFeaturesVisualTests` - Visual verification of Magic Fix UI
> - `VisualEditingTests` - Visual verification of editor UI
> - `VisualRecordingTests` - Visual verification of recording UI
>
> These require manual visual inspection and are not suitable for automated CI/CD.

### Tier 1: Unit Tests (Fast, <1s) - ✅ Active

- **Target**: `SaneVideoTests`
- **Scope**: Isolated logic, regex parsing, state machines, math algorithms.
- **Data**: Mocked services, small buffers. **NO** file I/O or app launching.
- **Goal**: Verify logic instantly.
- **Run**: `./Scripts/SaneMaster.rb verify` (runs unit tests by default)

### Tier 2: Integration/UI Tests (Real-World, 10s-60s) - ✅ Active (Code Tests Only)

- **Target**: `SaneVideoUITests` (excluding visual test classes)
- **Scope**: End-to-end user flows, AVFoundation pipeline, CoreML execution.
- **Data**: Real assets (`Tests/Assets/test_video.mp4` or `test_silence.mp4`).
- **Goal**: Verify system stability and functional output.
- **Excluded**: Visual test classes (see above) - these require manual inspection
- **Run**: `./Scripts/SaneMaster.rb verify --ui` (includes functional UI tests, excludes visual tests)

### Tier 3: Performance & Robustness

- **Objective**: Prevent regressions in export speed and memory usage.
- **Location**: `SaneVideoUITests/SaneEditorFeatureTests.swift` -> `testExportPerformance`
- **Metrics**: Uses `XCTClockMetric` and `XCTMemoryMetric`.
- **Large Assets**: All Timeline UIs MUST use `LazyHStack` or equivalent JIT loading to support 10h+ videos without OOM.
- **Command**: `xcodebuild test ... -only-testing:SaneVideoUITests/SaneEditorFeatureTests/testExportPerformance`
- **Best Practice**: Run before releases. Inspect memory deltas to catch leaks.

### Additional Testing Tools

Use these tools for comprehensive code validation:

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

3. **Test Execution**:

   ```bash
   ./Scripts/SaneMaster.rb verify           # Build + run unit tests (default)
   ./Scripts/SaneMaster.rb verify --ui      # Build + run unit + functional UI tests (excludes visual tests)
   ```

4. **Manual Visual Testing**: Visual tests (`SaneSmartFeaturesVisualTests`, `VisualEditingTests`, `VisualRecordingTests`) require manual inspection and are not automated.

### Regression Testing (MANDATORY)

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
- **Test Creation**: Use `./Scripts/SaneMaster.rb gen_test` to generate new tests as you fix bugs or add features.

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
- **Log Output**: `SaneMaster.rb` automatically mirrors raw test logs to `test_output.txt` to prevent terminal freezes.
- **Test Hygiene**: `test_output.txt` is automatically removed by `./Scripts/SaneMaster.rb clean`. If running manual `xcodebuild`, please redirect output manually (`> output.txt 2>&1`) and clean up afterwards.

### Test Anti-Patterns (NEVER DO THIS)

**These patterns always pass and provide zero value:**

| ❌ Anti-Pattern | Why It's Wrong | ✅ Correct Approach |
|----------------|----------------|---------------------|
| `#expect(true)` or `#expect(true, "message")` | Verifies nothing - always passes | `#expect(result == expectedValue)` |
| `#expect(a == true \|\| a == false)` | Tautology - always passes | `#expect(a == expectedValue)` |
| `#expect(a != b \|\| a == b)` | Tautology - always passes | `#expect(a == b)` or `#expect(a != b)` |
| `#expect(type(of: x) == Type.self)` | Type check is always true if x is Type | `#expect(x.property == expectedValue)` |
| `#expect(array.count >= 0)` | Array count is always >= 0 | `#expect(array.count == expectedCount)` |
| "Does not crash" tests | Only verify compilation, not behavior | Test actual state changes, return values, or error types |

**When a test fails**: Investigate WHY the code is wrong. Don't "fix" by weakening assertions to `#expect(true)`.

---

## 9. Documentation Structure

### Primary Documentation (Single Source of Truth)

- **DEVELOPMENT.md** (this file): Complete SOP, architecture, workflows, style guide. The ONLY authoritative source.
- **README.md**: User-facing features, quick start, keyboard shortcuts

### Reference Documentation

- **ROADMAP.md**: Discussed features for future consideration. Check when user asks "what features have we discussed?"
- **BUG_TRACKING.md**: Bug documentation and tracking
- **TEST_CREATION_WORKFLOW.md**: Test creation workflow (trigger: "enter test creation workflow")
- **TEST_COVERAGE_ANALYSIS.md**: Coverage analysis and gaps

**Rule**: When in doubt, refer to DEVELOPMENT.md. If information is missing, add it here rather than creating new files.

---

## 10. For AI Agents

### First Steps

1. **Read this entire file (DEVELOPMENT.md)** - It's the single source of truth
2. **Check ROADMAP.md** - If user asks about previously discussed features
3. **Use SaneMaster.rb** - Don't run raw xcodebuild commands
4. **Always dump logs** - Critical for debugging

### Mandatory Workflow After Code Changes

**CRITICAL**: After making any code changes, you **MUST** follow this workflow:

1. **Build the app**: `./Scripts/SaneMaster.rb verify`
2. **Kill old instances**: `killall -9 SaneVideo` (prevents stale state and zombie processes)
3. **Launch with logging**:
   - `./Scripts/SaneMaster.rb launch` (launches the app)
   - `./Scripts/SaneMaster.rb logs --follow` (monitors logs in real-time)
4. **Monitor logs**: Watch for errors, warnings, and the specific behavior you're debugging

**Why this matters**:
- Old instances can hold stale state and interfere with testing
- Live logs are essential for debugging user-reported issues
- This workflow enables real-time collaboration with the user
- You can see exactly what happens when the user tests the changes

**Exception**: Skip this workflow if the build fails - fix build errors first.

### Test Mode (Interactive Debugging)

When the user says **"test mode"**, enter an interactive debugging workflow:

```bash
./Scripts/SaneMaster.rb test_mode   # or just: ./Scripts/SaneMaster.rb tm
```

This command automatically:
1. Kills existing SaneVideo processes
2. Shows recent screenshots from `Screenshots/` folder (with timestamps)
3. Shows recent crash reports from `~/Library/Logs/DiagnosticReports/`
4. Builds the app
5. Launches the app
6. Shows debug log status

**All diagnostic resources to monitor:**
- **Debug log**: `~/Movies/SaneVideo/SaneVideo_Debug.log` (overwrites each launch)
- **Screenshots**: `Screenshots/` in project root
- **Crash reports**: `~/Library/Logs/DiagnosticReports/SaneVideo-*.ips`
- **Hang/spin reports**: `~/Library/Logs/DiagnosticReports/SaneVideo-*.spin` or `*.hang`
- **Xcode test results**: `~/Library/Developer/Xcode/DerivedData/SaneVideo-*/Logs/Test/*.xcresult`
- **System console**: `log show --predicate 'process == "SaneVideo"' --last 5m`
- **MetricKit reports**: Logged via `CrashReporter` in app (see `AppLogger.general`)

**Note**: When user says "logs" or "check logs", they mean ALL diagnostic resources above, not just the debug log file.

**Cross-reference timestamps**: When debugging, match screenshot timestamps (filename) with:
- Log entries (timestamp in log file)
- Crash report timestamps (file modification time)

**After each fix**: Re-run `test_mode` to rebuild, relaunch, and verify the fix works.

### Issue Tracking Workflow (CRITICAL - Don't Get Lost!)

When the user reports bugs or complaints, you **MUST** document them immediately to prevent:
- Forgetting issues mid-conversation
- Fixing the wrong thing
- Making the user repeat themselves

#### Step 1: Document Issues Immediately

When user reports a problem, **IMMEDIATELY** use TodoWrite to create entries:

```
Format: "BUG: [Component] - [Brief Description]"
Status: pending
```

**Good examples:**
- `BUG: Effects - Double yellow box around selected tile`
- `BUG: Timeline - Orphaned lock icon in bottom-left`
- `BUG: Video Preview - Crosshair showing when not dragging`

**Bad examples:**
- `Fix UI` (too vague)
- `Look into problem` (not specific)

#### Step 2: Capture Screenshot Evidence

**CRITICAL: Always check the MOST RECENT screenshot by timestamp, not just the one attached.**

When user posts a screenshot or says "check ss":

1. **Find the most recent screenshot by timestamp:**
```bash
# List recent screenshots sorted by modification time (newest first)
ls -lt Screenshots/*.png 2>/dev/null | head -5

# Or get the absolute most recent with full timestamp
stat -f "%Sm %N" -t "%Y-%m-%d %H:%M:%S" Screenshots/*.png 2>/dev/null | sort -r | head -1
```

2. **Verify you're looking at the latest:**
   - Compare screenshot timestamp with current time
   - If user says "check ss", they mean the MOST RECENT one
   - Don't assume the attached screenshot is the latest - verify!

3. **Add screenshot reference to the todo item:**
   - `BUG: Effects - Double yellow box (SS: 10.02.23 PM)`
   - Always include the timestamp from the filename

**Common mistake**: Looking at an old screenshot when user has taken a new one. Always check timestamps first!

#### Step 3: Correlate with Logs

```bash
# Check what was happening at screenshot time
./Scripts/SaneMaster.rb logs --tail 50

# For specific timestamps, check the log file directly
grep "22:02" ~/Movies/SaneVideo/SaneVideo_Debug.log
```

#### Step 4: Verification After Each Fix

After deploying a fix, **VERIFY** with the user by:

1. **Build timestamp check**: Confirm new binary is deployed
   ```bash
   stat -f "%Sm" "/path/to/SaneVideo.app/Contents/MacOS/SaneVideo"
   ```

2. **Screenshot comparison**: Ask user to test and compare against original screenshot

3. **Update todo status**:
   - `completed` - User confirmed fixed
   - `pending` - Not yet addressed
   - `in_progress` - Currently working on

4. **NEVER mark as completed until user confirms** or you visually verify via screenshot

#### Issue Tracking Template

When entering test mode, maintain this mental checklist:

```
REPORTED ISSUES:
[ ] Issue 1: [Description] - Screenshot: [timestamp] - Status: [pending/fixed]
[ ] Issue 2: [Description] - Screenshot: [timestamp] - Status: [pending/fixed]
...

VERIFIED FIXES:
[x] Issue A: [Description] - Confirmed via screenshot [timestamp]
[x] Issue B: [Description] - Confirmed via logs showing [evidence]
```

#### Anti-Patterns to Avoid

1. ❌ **Claiming "fixed" without verification** - Always rebuild, deploy, and check
2. ❌ **Forgetting issues** - Document IMMEDIATELY in TodoWrite
3. ❌ **Fixing symptoms** - Look for root cause, not just what's visible
4. ❌ **Moving on before confirming** - User says "fixed" before you mark complete
5. ❌ **Ignoring old screenshots** - Always check latest screenshot by TIMESTAMP, not just the one attached
   - **MANDATORY**: Run `ls -lt Screenshots/*.png | head -5` to see most recent
   - **MANDATORY**: Compare screenshot timestamp with current time
   - User saying "check ss" means check the MOST RECENT screenshot

#### Quick Commands for Issue Tracking

```bash
# See recent screenshots (sorted by modification time, newest first)
ls -lt Screenshots/*.png | head -5

# Get absolute most recent with full timestamp
stat -f "%Sm %N" -t "%Y-%m-%d %H:%M:%S" Screenshots/*.png 2>/dev/null | sort -r | head -1

# Check build timestamp (is this a fresh build?)
stat -f "%Sm" "$(find ~/Library/Developer/Xcode/DerivedData -name 'SaneVideo.app' -type d | head -1)/Contents/MacOS/SaneVideo"

# Watch logs while user tests
./Scripts/SaneMaster.rb logs --follow

# Kill, rebuild, deploy cycle
killall -9 SaneVideo; ./Scripts/SaneMaster.rb verify && ./Scripts/SaneMaster.rb launch
```

### Post-Fix Checklist (MANDATORY)

After fixing ANY bug, you **MUST** complete this checklist:

- [ ] **Regression test added?** - Every bug fix MUST have a test that would have caught it
      ```bash
      ./Scripts/SaneMaster.rb gen_test RegressionTests --target <Component>
      ```
- [ ] **Similar bugs checked?** - Search for the same pattern elsewhere in codebase
      ```bash
      # Example: if you fixed a timeout race condition, search for other timeouts
      grep -r "Task.*sleep" SaneVideo/
      ```
- [ ] **Changes committed?** - Don't lose work! Commit after each fix
      ```bash
      git add -A && git commit -m "Fix: <description>"
      ```
- [ ] **Plain English explanation?** - Can you explain what broke and why in simple terms?
- [ ] **Technical debt tracked?** - Any TODOs or FIXMEs added? Track them:
      ```bash
      grep -rn "TODO\|FIXME" SaneVideo/ | head -20
      ```

**Why this matters:**
- Regression tests prevent the same bug from coming back
- Similar bugs often exist nearby (copy-paste, same pattern)
- Uncommitted work can be lost
- You (the user) should always understand what was fixed
- TODOs get forgotten if not tracked

**Useful follow-up commands:**
```bash
./Scripts/SaneMaster.rb logs --follow  # Watch logs live
./Scripts/SaneMaster.rb crashes        # Analyze crash patterns
open Screenshots/                       # View screenshots
```

### Memory MCP Usage (Cross-Session Knowledge)

The Memory MCP persists valuable knowledge across sessions. Bootstrap automatically displays a summary of stored knowledge.

**Entity Types:**
- `bug_pattern` - Recurring bugs with symptoms, root cause, and fix
- `concurrency_gotcha` - Swift 6 concurrency pitfalls and solutions
- `file_violation` - Files exceeding size limits needing refactoring
- `architecture_pattern` - Key architectural decisions
- `service` - Service responsibilities and concurrency notes
- `compliance_rule` - SOP rules agents frequently violate

**When to READ:**
- Bootstrap shows summary automatically
- Before bug fix: `mcp__memory__search_nodes("bug_pattern")`
- Before concurrency work: `mcp__memory__search_nodes("concurrency")`
- Full details: `./Scripts/SaneMaster.rb memory_context`

**When to WRITE:**
- After bug fix (>30 min diagnosis): Create `bug_pattern` entity
- After concurrency fix: Create/update `concurrency_gotcha`
- After architecture decision: Create `architecture_pattern`

**Rule**: If it took >30 minutes to figure out, write it to memory.

**Commands:**
```bash
./Scripts/SaneMaster.rb memory_context   # Show all stored knowledge
./Scripts/SaneMaster.rb memory_record    # Add new entity (interactive)
./Scripts/SaneMaster.rb memory_prune     # Clean up stale entities
```

**Post-Fix Checklist Addition:**
- [ ] Memory updated? (If pattern worth remembering across sessions)

### Session Reviews (MANDATORY)

At session end, store learnings to memory for cross-session improvement.

**Query past learnings at session start:**
```
mcp__memory__search_nodes("SaneVideo mistakes patterns")
```

**Store new learnings at session end** (naming: `SessionReview_YYYY-MM-DD_TaskName`):
- Tasks completed, build failures, self-rating (1-10)
- Mistakes made with root cause
- Patterns discovered (API gotchas, codebase quirks)

This prevents repeating mistakes and builds institutional knowledge.

### Documentation Priority

1. **DEVELOPMENT.md** - Always check here first
2. **README.md** - For user-facing features
3. **Reference docs** - Only when needed for specific topics
4. **Historical docs** - For context only, not as source of truth

### When Adding Documentation

- **Add to DEVELOPMENT.md** if it's a rule, workflow, or architecture detail
- **Add to README.md** if it's user-facing
- **Create reference doc** only if it's a large, specialized topic that doesn't fit in DEVELOPMENT.md
- **Don't create** new documentation files for small updates

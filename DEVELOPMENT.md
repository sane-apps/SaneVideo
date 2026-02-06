# SaneVideo Development Guide (SOP)

**Version 2.1** | Last updated: 2026-02-02

> **SINGLE SOURCE OF TRUTH** for all Developers and AI Agents.

---

## Sane Philosophy

```
┌─────────────────────────────────────────────────────┐
│           BEFORE YOU SHIP, ASK:                     │
│                                                     │
│  1. Does this REDUCE fear or create it?             │
│  2. Power: Does user have control?                  │
│  3. Love: Does this help people?                    │
│  4. Sound Mind: Is this clear and calm?             │
│                                                     │
│  Grandma test: Would her life be better?            │
│                                                     │
│  "Not fear, but power, love, sound mind"            │
│  — 2 Timothy 1:7                                    │
└─────────────────────────────────────────────────────┘
```

→ Full philosophy: `~/SaneApps/meta/Brand/NORTH_STAR.md`

---

## ⚠️ THIS HAS BURNED YOU

Real failures from past sessions. Don't repeat them.

| Mistake | What Happened | Prevention |
|---------|---------------|------------|
| **Guessed API** | `await scheduleSegment` blocks forever (waits for playback, not scheduling) | `verify_api` first |
| **Assumed Swift binding** | MTAudioProcessingTap C API ≠ Swift API. Hours wasted. | Check `apple-docs` MCP |
| **Wrong parameter** | `onKeyPress` does NOT have a `modifiers:` parameter. 30 min wasted. | Check docs first |
| **Kept guessing** | Hidden Button + keyboardShortcut = EXC_BAD_ACCESS. 4 attempts. | Stop at 2, investigate |
| **Deleted "unused" file** | Periphery said unused, but ServiceContainer needed it | Grep before delete |
| **Skipped xcodegen** | Created file, "file not found" for 20 minutes | `xcodegen generate` after new files |

**The #1 differentiator**: Skimming this SOP = 5/10 sessions. Internalizing it = 8+/10.

### Why Catchy Rule Names?

Memorable rules + clear tool names = **human can audit in real-time**.

Names like "SANEMASTER OR DISASTER" aren't just mnemonics—they're a **shared vocabulary**. When I say "Rule #5" you instantly know whether I'm complying or drifting. This lets you catch mistakes as they happen instead of after 20 minutes of debugging.

---

## 🚀 Quick Start for AI Agents

**New to this project? Start here:**

1. **Read Rule #0 first** (Section 1) - It's about HOW to use all other rules
2. **All files stay in project** - NEVER write files outside `/Users/sj/SaneApps/apps/SaneVideo/` unless user explicitly requests it
3. **Use SaneMaster.rb for everything** - `./scripts/SaneMaster.rb verify` for build+test, never raw `xcodebuild`
4. **Self-rate after every task** - Rate yourself 1-10 on SOP adherence (see Section 1)

Bootstrap runs automatically via SessionStart hook. If it fails, run `./scripts/SaneMaster.rb doctor`.

**Your first action when user says "check our SOP" or "use our SOP":**
```bash
./scripts/SaneMaster.rb bootstrap  # Verify environment (may already have run)
./scripts/SaneMaster.rb verify     # Build + unit tests
```

**Key Commands:**

```bash
./scripts/SaneMaster.rb bootstrap  # Environment check + auto-update (runs on session start)
./scripts/SaneMaster.rb verify     # Build + unit tests (fast, ~30s)
./scripts/SaneMaster.rb verify --ui  # Build + unit + UI tests (~60s)
./scripts/SaneMaster.rb test_suite --quick  # Comprehensive validation
```

**SOP Loop Commands (Two-Fix Rule Enforcement):**

```bash
./scripts/SaneMaster.rb verify_gate       # Run verify with failure tracking (--json for structured output)
./scripts/SaneMaster.rb sop_loop <prompt> # Start SOP-compliant task loop with auto-verification
./scripts/SaneMaster.rb reset_escalation  # Clear escalation state after investigation
```

The SOP loop enforces the **Two-Fix Rule**: After 2 consecutive `verify` failures, you MUST stop guessing and investigate:
1. `./scripts/SaneMaster.rb verify_api <API>` - Verify API exists in SDK
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
  "SessionStart": [{ "command": "./scripts/SaneMaster.rb bootstrap" }]
}
```

This runs automatically when you open the project. If bootstrap fails:
1. Check the error message
2. Run `./scripts/SaneMaster.rb doctor` for diagnostics
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

**All other docs are historical/archive - refer to DEVELOPMENT.md first.**

---

## 0. Critical System Context: macOS 26.2 (Tahoe)

- **OS**: macOS 26.2 (Tahoe). APIs differ from older versions.
- **Hardware**: Apple Silicon (M1+) ONLY. No Intel support.
- **Ruby**: Homebrew Ruby 3.4+ required. System Ruby 2.6 is deprecated. A `.ruby-version` file is provided for version managers. **NEVER use Python for tooling—Ruby only.** Python has caused environment conflicts.
- **Rule**: If unsure about an API, **CHECK THE SDK FIRST** (see SDK verification workflow in Golden Rules), then search the web for context/usage. Do not guess.

---

## 1. The Golden Rules

### #0: NAME THE RULE BEFORE YOU CODE

✅ DO: State which rules apply before writing code
❌ DON'T: Start coding without thinking about rules

🟢 RIGHT: "This uses AVFoundation API → Rule #2: VERIFY BEFORE YOU TRY"
🟢 RIGHT: "New file needed → Rule #9: NEW FILE? GEN THAT PILE"
🔴 WRONG: "Let me just start coding..."
🔴 WRONG: "I'll figure out the rules as I go"

---

### #1: STAY IN YOUR LANE

✅ DO: Save all files inside `/Users/sj/SaneApps/apps/SaneVideo/`
❌ DON'T: Create files outside project without asking

🟢 RIGHT: `/Users/sj/SaneApps/apps/SaneVideo/Scripts/new_helper.rb`
🟢 RIGHT: `/Users/sj/SaneApps/apps/SaneVideo/Core/Models/NewModel.swift`
🔴 WRONG: `~/.claude/plans/my-plan.md`
🔴 WRONG: `/tmp/scratch.swift`

If file must go elsewhere → ask user where.

---

### #2: VERIFY BEFORE YOU TRY

✅ DO: Run verify_api before using any Apple API
❌ DON'T: Assume an API exists from memory or web search

🟢 RIGHT: `./scripts/SaneMaster.rb verify_api AVCaptureDevice AVFoundation`
🟢 RIGHT: `./scripts/SaneMaster.rb verify_api kAXExtrasMenuBarAttribute Accessibility`
🔴 WRONG: "I remember AVCaptureDevice has a .zoom property"
🔴 WRONG: "Stack Overflow says use .preferredCamera"

---

### #3: TWO STRIKES? INVESTIGATE

✅ DO: After 2 failures → stop, run verify_api, check docs
❌ DON'T: Guess a third time without researching

🟢 RIGHT: "Failed twice. Running verify_api to check if this API exists."
🟢 RIGHT: "Two attempts failed. Checking apple-docs MCP for correct usage."
🔴 WRONG: "Let me try a slightly different approach..." (attempt #3)
🔴 WRONG: "Maybe if I change this one thing..." (attempt #4)

---

### #4: GREEN MEANS GO

✅ DO: Fix all verify failures before claiming done
❌ DON'T: Ship with failing tests

🟢 RIGHT: "verify failed → fixing the error → running verify again"
🟢 RIGHT: "Tests pass. Ready to ship."
🔴 WRONG: "verify failed but it's probably fine"
🔴 WRONG: "I'll fix that test later"

---

### #5: SANEMASTER OR DISASTER

✅ DO: Use `./scripts/SaneMaster.rb` for all build/test operations
❌ DON'T: Use raw xcodebuild or xcode commands

🟢 RIGHT: `./scripts/SaneMaster.rb verify`
🟢 RIGHT: `./scripts/SaneMaster.rb verify_api MyAPI`
🔴 WRONG: `xcodebuild -scheme SaneVideo build`
🔴 WRONG: `xcrun xcodebuild test`

---

### #6: BUILD, KILL, LAUNCH, LOG

✅ DO: Run full sequence after every code change
❌ DON'T: Skip steps or assume it works

🟢 RIGHT:
```bash
./scripts/SaneMaster.rb verify    # BUILD
killall -9 SaneVideo              # KILL
./scripts/SaneMaster.rb launch    # LAUNCH
./scripts/SaneMaster.rb logs --follow  # LOG
```
🟢 RIGHT: `./scripts/SaneMaster.rb test_mode` (runs all steps)
🔴 WRONG: `./scripts/SaneMaster.rb verify` then "done!"
🔴 WRONG: Launch without killing old instance first

---

### #7: NO TEST? NO REST

✅ DO: Every bug fix gets a test that verifies the fix
❌ DON'T: Use placeholder or tautology assertions

🟢 RIGHT: `#expect(error.code == .invalidInput)`
🟢 RIGHT: `#expect(result.count == 3)`
🔴 WRONG: `#expect(true)`
🔴 WRONG: `#expect(value == true || value == false)`

---

### #8: BUG FOUND? WRITE IT DOWN

✅ DO: Document bugs in TodoWrite immediately, GitHub Issues after
❌ DON'T: Try to remember bugs or skip documentation

🟢 RIGHT: TodoWrite: "BUG: Camera - black screen on launch"
🟢 RIGHT: Create GitHub issue with root cause after fix
🔴 WRONG: "I'll remember to fix that later"
🔴 WRONG: Fix bug without documenting what caused it

---

### #9: NEW FILE? GEN THAT PILE

✅ DO: Run `xcodegen generate` after creating any new file
❌ DON'T: Create files without updating project

🟢 RIGHT: Create `NewService.swift` → run `xcodegen generate`
🟢 RIGHT: Create `NewView.swift` in Views/ → run `xcodegen generate`
🔴 WRONG: Create file and wonder why Xcode can't find it
🔴 WRONG: Manually edit project.pbxproj

---

### #10: FIVE HUNDRED'S FINE, EIGHT'S THE LINE

✅ DO: Keep files under 500 lines, split by responsibility
❌ DON'T: Exceed 800 lines or split arbitrarily

🟢 RIGHT: Split `CameraManager.swift` → `CameraManager.swift` + `CameraManager+Capture.swift`
🟢 RIGHT: 650-line file with clear single responsibility = OK
🔴 WRONG: 900-line file "because it's all related"
🔴 WRONG: Split at line 400 mid-function to hit a number

---

### #11: TOOL BROKE? FIX THE YOKE

✅ DO: If SaneMaster fails, fix the tool itself
❌ DON'T: Work around broken tools

🟢 RIGHT: "Nuclear clean doesn't clear cache → fix verify.rb"
🟢 RIGHT: "Logs path wrong → fix test_mode.rb"
🔴 WRONG: "Nuclear clean doesn't work → run raw xcodebuild"
🔴 WRONG: "Logs broken → just skip checking logs"

Working around broken tools creates invisible debt. Fix once, benefit forever.

---

### #12: TALK WHILE I WALK

✅ DO: Use subagents for heavy lifting, stay responsive to user
❌ DON'T: Block on long operations

🟢 RIGHT: "User asked question → answer while subagent keeps working"
🟢 RIGHT: "Long task → spawn subagent, stay responsive"
🔴 WRONG: "Hold on, let me finish this first..."
🔴 WRONG: "Running verify... (blocks for 2 minutes)"

User talks, you listen, work continues uninterrupted.

---

### PLAN FORMAT (MANDATORY)

Every plan must cite which rule justifies each step. No exceptions.

**Format**: `[Rule #X: NAME] - specific action with file:line or command`

#### ❌ DISAPPROVED PLAN (Real Example - Magic Fix Bug)

```
## Plan: Fix Magic Fix Playback

### Problem
Play button doesn't reset after Magic Fix completes.

### Steps
1. Find where Magic Fix updates state
2. Add loadProject call after completion
3. Rebuild and test

Approve?
```

**Why rejected:**
- No `[Rule #X]` citations - can't verify SOP compliance
- No test specified (violates Rule #5: Regression Tests)
- No GitHub issue created (violates Rule #8)
- "Find where" is vague - should have file:line

#### ✅ APPROVED PLAN (Same Task, Correct Format)

```
## Plan: Fix Magic Fix Playback Reset

### Bug Details
| Symptom | File:Line | Root Cause |
|---------|-----------|------------|
| Play button stuck after Magic Fix | ProjectState+SmartFeatures.swift:250 | StateChangePipeline doesn't see removedRanges change |

### Steps

[Rule #5: REGRESSION TEST] - Create test:
  - SaneVideoTests/Regression/MagicFixRegressionTests.swift
  - `testPlaybackResetsAfterMagicFix()`

[Rule #8: DOCUMENT BUG] - Create GitHub issue:
  - BUG-XXX: Magic Fix doesn't trigger timeline reload

[Rule #6: FULL CYCLE] - Fix and verify:
  - Edit ProjectState+SmartFeatures.swift:254
  - Add `loadProject(forceReload: true)` + `seek(to: .zero)`
  - `./scripts/SaneMaster.rb verify`
  - `killall -9 SaneVideo && ./scripts/SaneMaster.rb launch`
  - `./scripts/SaneMaster.rb logs --follow`

[Rule #4: VERIFY BEFORE SHIP] - All tests pass, logs clean

Approve?
```

**Why approved:**
- Every step cites its justifying rule
- Regression test specified with exact file path
- GitHub issue creation included
- Specific file:line references
- Clear verification sequence

---

### SELF-RATING (MANDATORY)

✅ DO: Rate 1-10 after every task with specific ✅/❌ items
❌ DON'T: Skip rating or give vague justification

🟢 RIGHT:
```
**Self-rating: 7/10**
✅ Used SaneMaster, ran verify, added regression test
❌ Forgot to check logs after launch
```
🟢 RIGHT:
```
**Self-rating: 9/10**
✅ Verified API before using, full test cycle, logs clean
❌ Minor: could have used TodoWrite for tracking
```
🔴 WRONG: "Self-rating: 10/10" (no explanation)
🔴 WRONG: "Self-rating: 8/10 - did good" (vague)

| 9-10 | All rules followed | 5-6 | Notable gaps |
| 7-8 | Minor miss | 1-4 | Multiple violations |

---

### COMPREHENSIVE REVIEWS

When user asks for "full review" or "audit", launch parallel subagents:

```bash
Task(Explore): "file size violations"
Task(Explore): "test coverage gaps"
Task(Explore): "dead code"
Task(Explore): "crash patterns"
```

---

## 2. Quick Start

### The "One-Stop" Script

```bash
# Setup dependencies and environment
./scripts/SaneMaster.rb setup

# Verify everything (Build + Tests)
./scripts/SaneMaster.rb verify

# Generate usage assets (e.g. tests)
./scripts/SaneMaster.rb gen_assets
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
./scripts/SaneMaster.rb verify

# Include functional UI tests (excludes visual tests - manual only)
./scripts/SaneMaster.rb verify --ui

# Optional: Full Clean Build (Slow, ~30s)
./scripts/SaneMaster.rb verify --clean
```

#### 2. Full System Check (Slow, Complete)

Use this before pushing code. **Note**: Visual tests are excluded from automated runs (manual testing only).

```bash
bundle exec fastlane verify_full
```

#### 3. Analyzing Logs

Always diagnostics after a run:

```bash
./scripts/SaneMaster.rb diagnose --dump
```

*Why?* This ensures you see "ProjectStore initialized at..." and other critical runtime events that Xcode/MCP might swallow.

#### 4. Test Mode vs Verify: When to Use Which

| Scenario | Command | What It Does |
|----------|---------|--------------|
| After code changes | `./scripts/SaneMaster.rb verify` | Build + run unit tests (automated, ~30s) |
| Before committing | `./scripts/SaneMaster.rb verify --ui` | Build + unit + UI tests (automated, ~60s) |
| User testing live | See "Test Mode" below | Kill → Build → Launch → Stream logs |
| Debugging crash | See Section 6 | Crash analysis workflow |

**Key distinction:**
- **`verify`** = Automated, no user interaction, confirms code compiles and tests pass
- **Test Mode** = Interactive, user provides feedback, you watch logs in real-time

**Test Mode workflow (when user says "test mode" or you need live debugging):**
```bash
./scripts/SaneMaster.rb test_mode   # Preferred: runs all steps below automatically
# Or manually: killall -9 SaneVideo && ./scripts/SaneMaster.rb verify && ./scripts/SaneMaster.rb launch
# Then: ./scripts/SaneMaster.rb logs --follow   # Stream logs
```

Monitor these resources while user tests:
- **Debug log**: `~/Movies/SaneVideo/SaneVideo_Debug.log`
- **Screenshots**: `Screenshots/` in project root
- **Crash reports**: `~/Library/Logs/DiagnosticReports/SaneVideo-*.ips`

---

## 5A. Research Protocol

This is the standard protocol for investigating problems. Used by Rule #3, Circuit Breaker, and any time you're stuck.

### Tools to Use (ALL of them)

| Tool | Purpose | When to Use |
|------|---------|-------------|
| **Task agents** | Explore codebase, analyze patterns | "Where is X used?", "How does Y work?" |
| **apple-docs MCP** | Verify Apple APIs exist and usage | Any Apple framework API |
| **context7 MCP** | Library documentation | Third-party packages (WhisperKit, KeyboardShortcuts) |
| **WebSearch/WebFetch** | Solutions, patterns, best practices | Error messages, architectural questions |
| **Grep/Glob/Read** | Local investigation | Find similar patterns, check implementations |
| **memory MCP** | Past bug patterns, architecture decisions | "Have we seen this before?" |
| **verify_api** | SDK symbol verification | Before using any unfamiliar API |

### Research Output → Plan

After research, present findings in this format:

```
## Research Findings

### What I Found
- [Tool used]: [What it revealed]
- [Tool used]: [What it revealed]

### Root Cause
[Clear explanation of why the problem occurs]

### Proposed Fix

[Rule #X: NAME] - specific action
[Rule #Y: NAME] - specific action
...

### Verification
- [ ] ./scripts/SaneMaster.rb verify passes
- [ ] Manual test: [specific check]
```

### When to Use This Protocol

| Trigger | Action |
|---------|--------|
| **Rule #3**: 2 failures on same problem | STOP → Research Protocol → Plan |
| **Circuit Breaker**: Blocked by 3x same error or 5 total | STOP → Research Protocol → Plan → User approves reset |
| **Unfamiliar API** | Research Protocol (lighter: just verify_api + docs) |
| **Architectural question** | Research Protocol → discuss with user |

---

## 5B. Circuit Breaker Protocol

The circuit breaker is an automated safety mechanism that **blocks Edit/Bash/Write tools** after repeated failures. This prevents runaway loops.

### When It Triggers

| Condition | Threshold | Meaning |
|-----------|-----------|---------|
| **Same error 3x** | 3 identical | Stuck in loop, repeating same mistake |
| **Total failures** | 5 any errors | Flailing, time to step back |

Success resets the counter. Normal iterative development (fail → fix → fail → fix → succeed) works fine.

### Commands

```bash
./scripts/SaneMaster.rb breaker_status  # Check if tripped
./scripts/SaneMaster.rb breaker_errors  # See what failed
./scripts/SaneMaster.rb reset_breaker   # Unblock (after plan approved)
```

### Recovery Flow

When blocked, follow the **Research Protocol** (section above). Start with `breaker_errors` to see what failed.

```
🔴 CIRCUIT BREAKER TRIPS
         │
         ▼
┌─────────────────────────────────────────────┐
│  1. READ ERRORS                             │
│     ./scripts/SaneMaster.rb breaker_errors  │
├─────────────────────────────────────────────┤
│  2. RESEARCH (use ALL tools above)          │
│     - What API am I misusing?               │
│     - Has this bug pattern happened before? │
│     - What does the documentation say?      │
├─────────────────────────────────────────────┤
│  3. PRESENT SOP-COMPLIANT PLAN              │
│     - State which rules apply               │
│     - Show what research revealed           │
│     - Propose specific fix steps            │
├─────────────────────────────────────────────┤
│  4. USER APPROVES PLAN                      │
│     User runs: ./scripts/SaneMaster.rb      │
│                reset_breaker                │
└─────────────────────────────────────────────┘
         │
         ▼
    🟢 EXECUTE APPROVED PLAN
```

**Key insight**: Being blocked is not failure—it's the system working. The research phase often reveals the root cause that guessing would never find.

---

## 5C. Memory Health & Maintenance

The Memory MCP can bloat and fill context window. Monitor and maintain regularly.

### Commands

```bash
./scripts/SaneMaster.rb mh              # Check entity/token counts
./scripts/SaneMaster.rb mcompact --dry-run  # Preview compaction
./scripts/SaneMaster.rb mcleanup        # Generate MCP cleanup commands (pipe memory JSON)
```

### Thresholds

| Metric | Warn | Critical |
|--------|------|----------|
| Entities | 60 | 80 |
| Tokens | 8000 | 12000 |
| Observations per entity | 15 | 25 |

### Auto-Maintenance

At session end, if thresholds are exceeded:
1. Old entities (>60 days) are archived to `.claude/memory_archive.jsonl`
2. Verbose entities get trimmed (keep first 5 + last 3 observations)
3. Cleanup commands are printed for manual execution

### When Memory Is Large

Run `mcp__memory__read_graph` and pipe to cleanup analysis:
```
"Read the memory graph and run ./scripts/SaneMaster.rb mcleanup"
```

This generates specific MCP commands to delete stale entities and trim verbose ones.

---

## 5D. SaneLoop: SOP Enforcement Loop

**Purpose**: Forces Claude to complete ALL SOP requirements before claiming a task is done.

**How it works**:
1. Run `/sane-loop` with a prompt containing SOP requirements
2. Claude works on the task
3. When Claude tries to exit, a Stop hook intercepts and feeds the prompt back
4. Claude sees previous work and iterates until completion criteria are met
5. Loop exits when `<promise>COMPLETE</promise>` appears or max iterations hit

**MANDATORY Rules** (learned from 700+ iteration failure on 2026-01-02):

| Rule | Requirement | Why |
|------|-------------|-----|
| **Always set `--max-iterations`** | Use 10-20, NEVER 0 or omit | Prevents infinite loops |
| **Always set `--completion-promise`** | Clear, verifiable text | Loop needs exit condition |
| **Promise must be TRUE** | Only output when genuinely complete | Don't lie to escape loop |

✅ DO:
```bash
/sane-loop "Fix bug X" --completion-promise "BUG-FIXED" --max-iterations 15
/sane-loop "Add feature Y" --completion-promise "FEATURE-COMPLETE" --max-iterations 20
```

❌ DON'T:
```bash
/sane-loop "Fix bug X"  # NO! Missing both required flags
/sane-loop "Fix bug X" --max-iterations 0  # NO! Unlimited = infinite loop
```

**Usage for bug fixes**:

```bash
/sane-loop "Fix: [describe bug]

SOP Requirements (verify before completing):
1. ./scripts/SaneMaster.rb verify passes
2. killall -9 SaneVideo && ./scripts/SaneMaster.rb launch
3. ./scripts/SaneMaster.rb logs --follow (check for errors)
4. Regression test added in SaneVideoTests/Regression/
5. GitHub issue created/updated
6. Self-rating 1-10 provided

Output <promise>SOP-COMPLETE</promise> ONLY when ALL verified." --completion-promise "SOP-COMPLETE" --max-iterations 10
```

**Commands**:
- `/sane-loop "<prompt>" --completion-promise "<text>" --max-iterations N` - Start loop
- `/cancel-ralph` - Cancel active loop

---

## 6. Troubleshooting

- **Ghost Beeps / No Launch**: Run `xcodegen generate`.
- **"Signal 9" Crash**: Check `SaneVideo.entitlements` for App Sandbox.
- **Phantom Errors**: Run `./scripts/SaneMaster.rb clean --nuclear`.
- **Permissions Black Screen**: Run `tccutil reset Camera`.
- **Test Execution**: Tests are working! Unit tests and functional UI tests run automatically. Visual tests are excluded (manual testing only).

### Crash/Log Analysis SOP (MANDATORY for Debugging)

**When to use this**: After ANY crash, freeze, or unexpected behavior. Run this **before** attempting fixes.

#### Quick Decision Tree

```
App problem?
    │
    ├─ App still running but misbehaving?
    │   └─ Check logs: ./scripts/SaneMaster.rb logs --follow
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

#### Step 0: Nuclear Relaunch

If app is malfunctioning, follow Rule #6 (kill → launch → logs). Don't just re-launch—zombie processes pollute logs.

#### Step 1: Analyze Crashes

```bash
./scripts/SaneMaster.rb crashes           # Summary of recent crashes
./scripts/SaneMaster.rb crashes --details  # Full stack traces
./scripts/SaneMaster.rb crashes --recent   # Most recent crash only
```

#### Step 2: Check Application Logs

**File-based logs** (recommended - always available):

```bash
# Show today's logs
./scripts/SaneMaster.rb logs

# Show last 100 lines
./scripts/SaneMaster.rb logs --tail 100

# Follow logs live (like tail -f)
./scripts/SaneMaster.rb logs --follow
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

1. **SaneMaster.rb** (`./scripts/SaneMaster.rb`): The master controller.
    - `bootstrap`: **Auto-runs on session start.** Full environment bootstrap with auto-update, rollback support, and session logging.
    - `verify`: Build app + run unit tests (default).
    - `verify --clean`: Full clean build + run unit tests.
    - `verify --ui`: Build + run unit tests + functional UI tests (excludes visual tests).
    - `doctor`: Health check (environment, assets, permissions, XcodeGen sync).
    - `console`: **Interactive Ruby REPL** (Pry) for debugging scripts. Requires: `bundle exec ./scripts/SaneMaster.rb console`
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
3. **Claude Code Plugins** (install via `/plugin install`):
    - **swift-lsp@claude-plugins-official**: ✅ Enabled - Provides Swift code intelligence (completion, go-to-definition, diagnostics)
    - **code-review@claude-plugins-official**: ✅ Enabled - Automated PR review with 4 parallel agents
    - **security-guidance@claude-plugins-official**: ✅ Enabled - Security vulnerability alerts during editing
    - **sane-loop@claude-plugins-official**: ✅ Enabled - **SOP Enforcement Loop** - Prevents task completion until verification criteria are met (see below)
4. **MCP Servers** (configured in `.mcp.json`):
    - **Note**: Ensure `enableAllProjectMcpServers: true` is set in `.claude/settings.json` and no restrictive `enabledMcpjsonServers` array exists.
    - **apple-docs**: ✅ Enabled - Apple Developer Documentation & WWDC transcripts (1,260+ sessions, 2012-2025). Use for API examples, related APIs, and understanding "why" behind APIs.
    - **github**: ✅ Enabled - GitHub API integration for issues, PRs, repos, and code search. (Official MCP)
    - **memory**: ✅ Enabled - Persistent knowledge graph for cross-session context. Provided by the claude-mem plugin (configured in `.claude/settings.json`), not a standalone MCP server entry.
    - **context7**: ✅ Enabled - Real-time, version-specific library documentation. Prevents hallucinated APIs by fetching current docs from source repos.

### When to Use Which Tool (Decision Matrix)

| Situation | Tool to Use | Why |
|-----------|-------------|-----|
| **Need API signature or existence** | `./scripts/SaneMaster.rb verify_api` | SDK is source of truth (Rule #6) |
| **Need API usage examples or WWDC context** | `apple-docs` MCP | Rich examples, related APIs, historical context |
| **Need up-to-date library docs (WhisperKit, Vapor, etc.)** | `context7` MCP | Fetches real-time docs from source repos |
| **Build/test the project** | `./scripts/SaneMaster.rb verify` | Always use SaneMaster (Rule #1) |
| **Generate mock classes** | `./scripts/SaneMaster.rb gen_mock` (Mockolo) | Fast protocol→mock generation |
| **Generate test templates** | `./scripts/SaneMaster.rb gen_test` | Creates structured unit/UI tests |
| **GitHub issues/PRs** | `github` MCP | Create issues, review PRs, search code |
| **Remember context across sessions** | `memory` MCP | Persistent knowledge graph |
| **Code intelligence (completions, go-to-def)** | `swift-lsp` plugin | IDE-like Swift support in Claude Code |

### Future: iOS/iPadOS Companion Apps

> **Current Focus**: macOS app until rock solid. iOS/iPad work comes later.

When developing the iPhone/iPad companion apps:
- Shared code should live in a Swift Package for cross-platform use
- Use `apple-docs` for platform-specific API differences (UIKit vs AppKit)

### Test Generation Tool

**Usage:**

```bash
# Generate unit test with Swift Testing framework (default)
./scripts/SaneMaster.rb gen_test MyFeatureTests --target MyFeature

# Generate UI test with XCTest
./scripts/SaneMaster.rb gen_test MyUITests --type ui --framework xctest

# Generate async test
./scripts/SaneMaster.rb gen_test AsyncTests --async
```

**Features:**

- ✅ Generates proper test structure following AAA pattern
- ✅ Includes timeout configuration
- ✅ Adds TestEnvironment helper methods
- ✅ Supports both Swift Testing and XCTest frameworks
- ✅ Handles async/await patterns
- ✅ Follows project conventions

**See the "Test Standards" section above** for test creation workflow and best practices.

### SaneLoop: SOP Enforcement Loop

**Purpose**: Forces Claude to complete ALL SOP requirements before claiming a task is done.

**How it works**:
1. You run `/sane-loop` with a prompt containing SOP requirements
2. Claude works on the task
3. When Claude tries to exit, a Stop hook intercepts and feeds the prompt back
4. Claude sees previous work and iterates until completion criteria are met
5. Loop exits when `<promise>COMPLETE</promise>` appears or max iterations hit

**Usage for bug fixes**:

```bash
/sane-loop "Fix: [describe bug]

SOP Requirements (verify before completing):
1. ./scripts/SaneMaster.rb verify passes
2. killall -9 SaneVideo && ./scripts/SaneMaster.rb launch
3. ./scripts/SaneMaster.rb logs --follow (check for errors)
4. Regression test added in SaneVideoTests/Regression/
5. Self-rating 1-10 provided

Output <promise>SOP-COMPLETE</promise> ONLY when ALL verified." --completion-promise "SOP-COMPLETE" --max-iterations 10
```

**Usage for features**:

```bash
/sane-loop "Implement: [describe feature]

Requirements: [list requirements]

SOP: verify passes, logs checked, self-rating provided.

<promise>FEATURE-DONE</promise>" --completion-promise "FEATURE-DONE" --max-iterations 15
```

**Commands**:
- `/sane-loop "<prompt>" --completion-promise "<text>" --max-iterations N` - Start loop
- `/cancel-ralph` - Cancel active loop

**When to use**:
- Complex bug fixes requiring multiple verification steps
- Feature implementations with many requirements
- Any task where Claude tends to skip SOP steps

**QA Criteria Pattern** (inspired by Auto-Claude):

For structured verification, use explicit acceptance criteria in your prompt:

```bash
/sane-loop "TASK: [description]

ACCEPTANCE CRITERIA:
1. [ ] Build passes: ./scripts/SaneMaster.rb verify
2. [ ] App launches without errors: killall -9 SaneVideo && ./scripts/SaneMaster.rb launch
3. [ ] No warnings in logs: ./scripts/SaneMaster.rb logs --follow
4. [ ] Regression test added (if bug fix)
5. [ ] Feature works as specified: [specific behavior to verify]

VERIFY EACH CRITERION with actual commands before outputting <promise>QA-PASS</promise>." --completion-promise "QA-PASS" --max-iterations 10
```

**Key principles**:
- Each criterion must be verifiable with a command
- Check boxes `[ ]` make status explicit
- Don't claim done until ALL boxes can be checked
- Max iterations prevents infinite loops

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
- **Run**: `./scripts/SaneMaster.rb verify` (runs unit tests by default)

### Tier 2: Integration/UI Tests (Real-World, 10s-60s) - ✅ Active (Code Tests Only)

- **Target**: `SaneVideoUITests` (excluding visual test classes)
- **Scope**: End-to-end user flows, AVFoundation pipeline, CoreML execution.
- **Data**: Real assets (`Tests/Assets/test_video.mp4` or `test_silence.mp4`).
- **Goal**: Verify system stability and functional output.
- **Excluded**: Visual test classes (see above) - these require manual inspection
- **Run**: `./scripts/SaneMaster.rb verify --ui` (includes functional UI tests, excludes visual tests)
- **ASSUME NOTHING**: Do not assume UI elements exist just because you wrote the View code. View hierarchies are complex. If element not found: `print(app.debugDescription)` to see actual hierarchy.

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
   ./scripts/SaneMaster.rb validate_test_references  # Verify UI test references match code
   ./scripts/SaneMaster.rb check_deprecations         # Find deprecated API usage
   ./scripts/SaneMaster.rb dead_code                  # Find unused code
   ./scripts/SaneMaster.rb lint                       # Code style and quality
   ```

2. **API Verification**:

   ```bash
   ./scripts/SaneMaster.rb verify_api <APIName> [Framework]  # Verify APIs exist in SDK
   ```

3. **Test Execution**:

   ```bash
   ./scripts/SaneMaster.rb verify           # Build + run unit tests (default)
   ./scripts/SaneMaster.rb verify --ui      # Build + run unit + functional UI tests (excludes visual tests)
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
- **Test Creation**: Use `./scripts/SaneMaster.rb gen_test` to generate new tests as you fix bugs or add features.

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
- **Test Hygiene**: `test_output.txt` is automatically removed by `./scripts/SaneMaster.rb clean`. If running manual `xcodebuild`, please redirect output manually (`> output.txt 2>&1`) and clean up afterwards.

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

## 8B. Known Architectural Debt

| Item | Status | Files | Impact |
|------|--------|-------|--------|
| ServiceContainer synchronous init | Open | `Core/DI/ServiceContainer.swift:123-205` | Slow launch, memory spike — 40+ services init synchronously |
| ControlsKit UI/Architecture coupling | Open | `Core/ControlsKit.swift:157,162` | SwiftUI Previews crash — IconCircleButtonStyle accesses ServiceContainer |
| Sample rate assumptions (mixed 48k/44.1k) | Partially fixed | VideoWriter, ScreenRecorder, WaveformService | Subtle A/V drift risk |
| Multiple export implementations | Monitor | ExportEngine, BatchExportService | Could diverge if one modified independently |
| NotificationCenter Magic Fix triggers | Monitor | SaneVideoApp, EditorLayoutView, SidebarView | Multi-window could trigger duplicate operations |

### Swift 6 Modernization: @preconcurrency Imports

Apple frameworks not yet Sendable-annotated. Remove when Apple updates:

| Framework | Files |
|-----------|-------|
| AVFoundation | PlaybackState, SaneVideoCompositor, AudioService, VoiceIsolation, CameraManager, AudioResampler, CameraFramePublisher |
| ScreenCaptureKit | ScreenRecorderProtocol, ScreenRecorder+Delegates, ScreenRecorder |
| Combine | CameraConcurrencyRegressionTests |

**Last audited**: 2025-12-31. Check each Xcode major release.

---

## 9. Documentation Structure

### Primary Documentation (Single Source of Truth)

- **DEVELOPMENT.md** (this file): Complete SOP, architecture, workflows, style guide. The ONLY authoritative source.
- **README.md**: User-facing features, quick start, keyboard shortcuts

### Reference Documentation

- **ROADMAP.md**: Discussed features for future consideration. Check when user asks "what features have we discussed?"
- **GitHub Issues**: Bug documentation and tracking at https://github.com/sj/SaneVideo/issues

**Rule**: When in doubt, refer to DEVELOPMENT.md. If information is missing, add it here rather than creating new files.

---

## 10. For AI Agents

> **Note**: First Steps and Mandatory Workflow are covered in Quick Start and Rule #5. This section covers interactive debugging specifics.

### Test Mode (Interactive Debugging)

When user says **"test mode"**: `./scripts/SaneMaster.rb test_mode` (kills processes, shows recent screenshots/crashes, builds, launches).

**Diagnostic resources** (when user says "logs" or "check logs", check ALL):
- `~/Movies/SaneVideo/SaneVideo_Debug.log` - Debug log (overwrites each launch)
- `Screenshots/` - Screenshots with timestamps
- `~/Library/Logs/DiagnosticReports/SaneVideo-*.ips` - Crash reports
- `log show --predicate 'process == "SaneVideo"' --last 5m` - System console

**Cross-reference timestamps** when debugging: match screenshot filename → log entries → crash reports.

### Issue Tracking Workflow

When user reports bugs, document **IMMEDIATELY** in TodoWrite:
```
Format: "BUG: [Component] - [Brief Description] (SS: [timestamp])"
Example: "BUG: Effects - Double yellow box (SS: 10.02.23 PM)"
```

**Screenshot rule**: Always check the MOST RECENT by timestamp, not the one attached:
```bash
ls -lt Screenshots/*.png | head -5  # Find latest screenshot
```

**Verification rule**: NEVER mark completed until user confirms or you verify via new screenshot.

**Anti-patterns**: ❌ Claiming "fixed" without rebuild/verify ❌ Forgetting issues ❌ Fixing symptoms not root cause

### Post-Fix Checklist

After fixing ANY bug:
- [ ] Regression test added? (`./scripts/SaneMaster.rb gen_test`)
- [ ] Similar bugs checked elsewhere? (`grep -r "pattern" SaneVideo/`)
- [ ] Changes committed?
- [ ] Plain English explanation ready?
- [ ] Memory updated? (if pattern worth remembering)

### Memory (Cross-Session Knowledge via claude-mem Plugin)

**Rule**: If it took >30 minutes to figure out, write it to memory. Memory is accessed via the claude-mem plugin, not as a standalone MCP server.

**Configuration**: Memory settings are in `.claude/settings.json`

**Entity types**: `bug_pattern`, `concurrency_gotcha`, `architecture_pattern`, `compliance_rule`

**Commands:**
```bash
mcp__plugin_claude-mem_mcp-search__search(query: "bug_pattern")  # Query before bug fix
./scripts/SaneMaster.rb memory_context                           # Show all stored knowledge
```

**Session reviews** (at session end): Store `SessionReview_YYYY-MM-DD_TaskName` with tasks completed, mistakes made, patterns discovered.

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

# SaneVideo - Claude Code Instructions

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

> **PRIME DIRECTIVE: READ THE PROMPTS**
> Hook fires → Read the message → Find the answer → Succeed first try.
> Don't skim. Don't guess. The answer is in front of you.

---

## Project Location

| Path | Description |
|------|-------------|
| **This project** | `~/SaneApps/apps/SaneVideo/` |
| **Save outputs** | `~/SaneApps/apps/SaneVideo/outputs/` |
| **Screenshots** | `~/Desktop/Screenshots/` (label with project prefix) |
| **Shared UI** | `~/SaneApps/infra/SaneUI/` |
| **Hooks/tooling** | `~/SaneApps/infra/SaneProcess/` |

**Sister apps:** SaneBar, SaneClip, SaneSync, SaneHosts, SaneAI, SaneClick

---

## Where to Look First

| Need | Check |
|------|-------|
| Build/test commands | `./Scripts/SaneMaster.rb --help` |
| Project structure | `project.yml` (XcodeGen config) |
| Past bugs/learnings | `.claude/memory.json` or MCP memory |
| Code patterns | `.claude/rules/` directory |
| Feature status | `ROADMAP.md` or `BUG_TRACKING.md` |
| Swift services | `SaneVideo/Services/` directory |
| UI components | `SaneVideo/UI/` directory |

---

## Quick Start

```bash
./Scripts/SaneMaster.rb verify          # Build + unit tests
ruby ./Scripts/qa.rb                   # Tooling QA checks (hooks + scripts)
ruby ./Scripts/hooks/test/tier_tests.rb # Run hook test tiers
```

## The 5 Core Rules

### 1. VERIFY BEFORE YOU TRY
Check docs/APIs exist before using them. Don't guess from memory.

**DO:** Check `.swiftinterface`, use `apple-docs` MCP, read type definitions
**DON'T:** "I remember this API has a .zoom property"

### 2. TWO STRIKES? INVESTIGATE
After 2 failures, STOP. Research. Don't guess a third time.

**DO:** "Failed twice. Checking SDK to verify this exists."
**DON'T:** "Let me try a slightly different approach..." (attempt #3)

### 3. TESTS MUST PASS
Fix all failures before claiming done. No tautologies (`#expect(true)`).

**DO:** Tests red → fix → run again → green → done
**DON'T:** "Tests failed but it's probably fine"

### 4. USE PROJECT TOOLS
Use SaneMaster, not raw commands. The tools exist for a reason.

**DO:** `./Scripts/SaneMaster.rb verify`
**DON'T:** `xcodebuild -scheme MyApp build`

### 5. STAY RESPONSIVE
Use subagents for heavy work. Answer user while tasks run.

**DO:** Spawn Task agent, keep responding to user
**DON'T:** "Hold on, let me finish this first..."

## Workflow

```
1. PLAN    → Understand task, identify files, state approach
2. VERIFY  → Check APIs exist before using
3. BUILD   → Make changes, run tests
4. CONFIRM → Tests pass, user approves
```

## When Hooks Block You

The hooks are helping, not fighting you:

| Block | Meaning | Fix |
|-------|---------|-----|
| Research incomplete | You skipped verification | Do the research first |
| MCP not verified | Didn't check MCP servers | Call read_graph, search_docs |
| Circuit breaker | 3+ failures in a row | Stop, investigate root cause |
| File too large | Over 500 lines | Split by responsibility |

## This Has Burned You Before

| Mistake | What Happened | Prevention |
|---------|---------------|------------|
| Guessed API | Used non-existent method, failed 4x | Rule #1: Verify first |
| Kept guessing | Same error 5 times, different "fixes" | Rule #2: Stop at 2 |
| Skipped tests | Shipped broken code | Rule #3: Tests pass |
| Raw xcodebuild | Missed project config | Rule #4: Use tools |

## Session End Format

```
## Session Summary
### Done: [1-3 bullet points]
### SOP: X/10 (rate RULE compliance, not task completion)
### Next: [Follow-up items]
```

## Project Structure

```
Scripts/
├── hooks/           # 4 enforcement hooks
│   ├── saneprompt.rb   # UserPromptSubmit
│   ├── sanetools.rb    # PreToolUse
│   ├── sanetrack.rb    # PostToolUse
│   └── sanestop.rb     # Stop
├── SaneMaster.rb    # Main CLI
└── qa.rb            # Quality checks
```

---

## MCP Tool Optimization (TOKEN SAVERS)

### XcodeBuildMCP Session Setup
At session start, set defaults ONCE to avoid repeating on every build:
```
mcp__XcodeBuildMCP__session-set-defaults:
  projectPath: /Users/sj/SaneVideo/SaneVideo.xcodeproj
  scheme: SaneVideo
  arch: arm64
```
Note: SaneVideo is a **macOS app** - no simulator needed. Use `build_macos`, `test_macos`, `build_run_macos`.

### claude-mem 3-Layer Workflow (10x Token Savings)
```
1. search(query, project: "SaneVideo") → Get index with IDs (~50-100 tokens/result)
2. timeline(anchor=ID)                → Get context around results
3. get_observations([IDs])            → Fetch ONLY filtered IDs
```
**Always add `project: "SaneVideo"` to searches for isolation.**

### apple-docs Optimization
- `compact: true` works on `list_technologies`, `get_sample_code`, `wwdc` (NOT on `search_apple_docs`)
- `analyze_api analysis="all"` for comprehensive API analysis
- `apple_docs` as universal entry point (auto-routes queries)

### context7 for Library Docs
- `resolve-library-id` FIRST, then `query-docs`
- SwiftUI ID: `/websites/developer_apple_swiftui` (13,515 snippets!)

### macos-automator (493 Pre-Built Scripts)
- `get_scripting_tips search_term: "keyword"` to find scripts
- `get_scripting_tips list_categories: true` to browse
- 13 categories including `13_developer` (92 Xcode/dev scripts)

### github MCP
- `search_code` to find patterns in public repos
- `search_repositories` to find reference implementations

---

## Claude Code Features (USE THESE!)

### Key Commands

| Command | When to Use | Shortcut |
|---------|-------------|----------|
| `/rewind` | Rollback code AND conversation after errors | `Esc+Esc` |
| `/context` | Visualize context window token usage | - |
| `/compact [instructions]` | Optimize memory with focus | - |
| `/stats` | See usage patterns (press `r` for date range) | - |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Esc+Esc` | Rewind to checkpoint |
| `Shift+Tab` | Cycle permission modes |
| `Option+T` | Toggle extended thinking |
| `Ctrl+B` | Background running task |

### Smart /compact Instructions

```
/compact keep SaneVideo video processing patterns and Metal performance learnings, archive general Swift tips
```

### Project Skills (Auto-Discovered)

Skills in `.claude/skills/` activate automatically:

| Skill | Triggers When |
|-------|---------------|
| `session-context-manager` | Checking memory health, session state |
| `memory-compactor` | Memory full, tokens high |
| `codebase-explorer` | Searching code, finding implementations |
| `audio-timeline-sync` | Audio/video sync questions |
| `metal-performance` | GPU/Metal optimization |
| `swift-concurrency` | Async/await patterns |

### Use Explore Subagent for Searches

```
Task tool with subagent_type: Explore
```

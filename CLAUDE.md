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
| Build/test commands | `./scripts/SaneMaster.rb --help` |
| Project structure | `project.yml` (XcodeGen config) |
| Past bugs/learnings | `.claude/memory.json` or MCP memory |
| Code patterns | `.claude/rules/` directory |
| Feature status | `ROADMAP.md` or [GitHub Issues](https://github.com/sj/SaneVideo/issues) |
| Swift services | `SaneVideo/Services/` directory |
| UI components | `SaneVideo/UI/` directory |

---

## Quick Start

```bash
./scripts/SaneMaster.rb verify          # Build + unit tests
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

**DO:** `./scripts/SaneMaster.rb verify`
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
└── SaneMaster.rb    # Main CLI (build, test, verify, gen_test, gen_mock, etc.)
```

Hooks are now managed globally at `~/SaneApps/infra/SaneProcess/`.

---

## MCP Tool Optimization (TOKEN SAVERS)

### Xcode Tools (Apple's Official MCP)
Requires Xcode running with the project open. Get the `tabIdentifier` first:
```
mcp__xcode__XcodeListWindows
mcp__xcode__BuildProject
mcp__xcode__RunAllTests
mcp__xcode__RenderPreview
```
Note: SaneVideo is a **macOS app**. Use `macos-automator` for real UI.

### Serena Memories
Use Serena for project-specific knowledge:
```
read_memory  # Check past learnings
write_memory # Save important findings
```
For cross-project knowledge graph, use official Memory MCP tools.

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

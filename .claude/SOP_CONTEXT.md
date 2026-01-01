# SOP ENFORCEMENT ACTIVE

You are working on **SaneVideo**. The following rules are MANDATORY.

---

## Before ANY Code Change

- [ ] Verify current state with `grep`/`find` (NOT memory - Rule #13)
- [ ] If API involved: `./Scripts/SaneMaster.rb verify_api <API> [Framework]` (Rule #1)
- [ ] Two-Fix Rule: If you fail twice, STOP and investigate — that's the win, not the failure (Rule #2)

## After ANY Code Change

```bash
./Scripts/SaneMaster.rb verify        # Build + test (Rule #4)
killall -9 SaneVideo                   # Kill old instances (Rule #5)
./Scripts/SaneMaster.rb launch         # Start fresh
./Scripts/SaneMaster.rb logs --follow  # Watch logs (Rule #6)
```

## For Bug Fixes (MANDATORY)

- [ ] Add regression test in `SaneVideoTests/Regression/` (Rule #7)
- [ ] Document in `BUG_TRACKING.md` if persistent (Rule #8)
- [ ] Search for similar patterns elsewhere: `grep -r "pattern" SaneVideo/`

## Before Claiming Done

- [ ] Self-rate 1-10 with checklist (MANDATORY)
- [ ] Format: `**Self-rating: X/10**` with what you did well / missed

---

## Ralph Loop Usage

For complex tasks requiring iteration, wrap in Ralph:

```bash
/ralph-loop "TASK: [description]

SOP Requirements:
1. verify passes
2. kill -> launch -> logs checked
3. regression test added (if bug fix)
4. self-rating provided

<promise>SOP-COMPLETE</promise> only when ALL verified." --completion-promise "SOP-COMPLETE" --max-iterations 10
```

---

## Session Start (MANDATORY - DO IMMEDIATELY)

**Before doing ANYTHING else, execute these two steps:**

1. **Check Memory** - Call `mcp__memory__read_graph` to load cross-session context
   - Bug patterns, architecture decisions, file violations already tracked
   - Recent fixes and learnings from past sessions

2. **Health Check** - Run `./Scripts/SaneMaster.rb health`

⚠️ **If you skipped memory check, STOP and do it now.** Past context prevents repeated mistakes.

## Session End

Run the session end command:

```bash
./Scripts/SaneMaster.rb session_end
```

This will:
- Prompt for memory-worthy insights (bug patterns, concurrency gotchas, architecture decisions)
- Auto-record insights to Memory MCP
- Show session summary with memory stats
- Warn if entity count > 60 (consolidation needed)

Note: The SessionEnd hook automatically runs `health` - no need to run it manually.

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `./Scripts/SaneMaster.rb health` | Quick health check (37ms) |
| `./Scripts/SaneMaster.rb verify` | Build + unit tests |
| `./Scripts/SaneMaster.rb verify --ui` | Build + all tests |
| `./Scripts/SaneMaster.rb test_mode` | Kill -> Build -> Launch -> Logs |
| `./Scripts/SaneMaster.rb logs --follow` | Stream live logs |
| `./Scripts/SaneMaster.rb verify_api X` | Check if API exists in SDK |

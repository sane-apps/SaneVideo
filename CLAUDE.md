# SaneVideo Project Configuration

> Project-specific settings that override/extend the global ~/CLAUDE.md

---

## Screenshots

**Screenshots are saved to the project folder, not Desktop.**

```bash
# ALWAYS check here FIRST for user screenshots:
ls -lat /Users/sj/SaneVideo/Screenshots/ | head -5
```

Do NOT check `~/Desktop` or other default locations.

---

## Project Structure

| Path | Purpose |
|------|---------|
| `Scripts/SaneMaster.rb` | Build tool - use instead of raw xcodebuild |
| `Screenshots/` | User screenshots (macOS default configured here) |
| `SaneVideoTests/Regression/` | Regression tests for bug fixes |
| `BUG_TRACKING.md` | Persistent bug documentation |

---

## Quick Commands

```bash
# Build & Test
./Scripts/SaneMaster.rb verify          # Build + unit tests
./Scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./Scripts/SaneMaster.rb logs --follow   # Stream live logs

# Memory Health (MCP Knowledge Graph)
./Scripts/SaneMaster.rb mh              # Check entity/token counts
./Scripts/SaneMaster.rb mcompact        # Compact verbose entities
./Scripts/SaneMaster.rb mcleanup        # Generate MCP cleanup commands

# Circuit Breaker (Failure Tracking)
./Scripts/SaneMaster.rb breaker_status  # Check if breaker is OPEN/CLOSED
./Scripts/SaneMaster.rb breaker_errors  # Show failure messages
./Scripts/SaneMaster.rb reset_breaker   # Reset after investigation

# Session Management
./Scripts/SaneMaster.rb session_end     # End session + memory prompt
./Scripts/SaneMaster.rb compliance      # Show session compliance report
```

---

## SaneVideo-Specific Patterns

- **Services**: Located in `SaneVideo/Services/` (CameraManager, AudioService, etc.)
- **State**: `AppState` with `@Observable`, child states for features
- **Views**: SwiftUI with extracted components in `Views/Components/`

---

## Compliance Engine

SaneVideo has automated SOP enforcement via hooks:

**Circuit Breaker** (`.claude/circuit_breaker.json`):
- Trips at: 3x same error OR 5 total failures
- When tripped: Edit/Bash tools blocked until reset
- Reset: `./Scripts/SaneMaster.rb reset_breaker`

**Memory Thresholds** (auto-checked at session start/end):
- Entities: 60 (warn), 80 (critical)
- Tokens: 8,000 (warn), 12,000 (critical)
- Archive: Old entities moved to `.claude/memory_archive.jsonl`

**Hooks Active** (in `.claude/settings.json`):
- `circuit_breaker.rb` - Pre-tool failure tracking
- `edit_validator.rb` - File location/size checks
- `test_quality_checker.rb` - Detects tautology tests
- `audit_logger.rb` - Decision trail to `.claude/audit_log.jsonl`

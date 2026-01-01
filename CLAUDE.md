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
./Scripts/SaneMaster.rb verify          # Build + unit tests
./Scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./Scripts/SaneMaster.rb logs --follow   # Stream live logs
```

---

## SaneVideo-Specific Patterns

- **Services**: Located in `SaneVideo/Services/` (CameraManager, AudioService, etc.)
- **State**: `AppState` with `@Observable`, child states for features
- **Views**: SwiftUI with extracted components in `Views/Components/`

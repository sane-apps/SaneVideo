# Testing Mode SOP

When the user says **"testing mode"**, enter this interactive manual testing workflow.

## Entry Protocol

1. **Kill all instances**
   ```bash
   pkill -x SaneVideo 2>/dev/null
   killall "SaneVideo" 2>/dev/null
   ```

2. **Clean if needed** (optional, ask user or use `--nuclear` for full clean)
   ```bash
   ./Scripts/SaneMaster.rb clean --nuclear
   ```

3. **Build fresh**
   ```bash
   xcodebuild -scheme SaneVideo -destination 'platform=macOS' build
   ```

4. **Clear test artifacts**
   ```bash
   rm -rf /tmp/SaneVideoTests 2>/dev/null
   rm -rf ~/Desktop/Screenshots/*.png 2>/dev/null
   ```

5. **Launch with live logs**
   ```bash
   # Option A: Direct launch with log streaming
   open /path/to/SaneVideo.app &
   log stream --predicate 'subsystem == "com.sanevideo.SaneVideo" OR process == "SaneVideo"' --style compact

   # Option B: Use SaneMaster
   ./Scripts/SaneMaster.rb launch --logs
   ```

## During Testing

- **User reports issue** -> I investigate logs + code
- **User shares screenshot** -> I analyze UI/UX issues AND correlate screenshot timestamp with logs
- **Bug found** -> I fix, rebuild, relaunch in-place
- **Bug fixed** -> I mark complete, user verifies

## Screenshot-Log Correlation

When user shares a screenshot:
1. Note the screenshot filename timestamp (e.g., `Screenshot 2025-12-27 at 3.35.55 PM.png`)
2. Convert to log query time: `--start "2025-12-27 15:35:50" --end "2025-12-27 15:36:00"`
3. Query logs around that exact moment:
   ```bash
   log show --predicate 'process == "SaneVideo"' --start "2025-12-27 15:35:50" --end "2025-12-27 15:36:00"
   ```
4. This gives "eyes" into what was happening at the exact moment of the screenshot

## Quick Commands

| Action | Command |
|--------|---------|
| Restart app | `pkill -x SaneVideo; open /path/to/app` |
| Rebuild + restart | `xcodebuild build && pkill -x SaneVideo && open /path/to/app` |
| View crash logs | `log show --predicate 'eventType == "crash"' --last 5m` |
| Clear DerivedData | `rm -rf ~/Library/Developer/Xcode/DerivedData/SaneVideo-*` |

## Exit Protocol

- Summarize all bugs found/fixed
- Update todo list with remaining issues
- Commit fixes if requested

## Distinction from "run tests"

- **"testing mode"** = Interactive manual testing with live app
- **"run tests"** = Automated unit/integration/UI tests via `xcodebuild test`

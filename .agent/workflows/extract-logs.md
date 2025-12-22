---
description: Automatically extract and display application logs from the latest UI test run.
---

### Extract Latest Test Logs

This workflow pulls the `StandardOutputAndStandardError` logs and identifies attachments (like screenshots) from the most recent `.xcresult` bundle.

// turbo

   ```bash
   ./Scripts/SaneMaster.rb diagnose
   ```

2. Review the printed logs for application-level prints (NSLog, print), SwiftUI warnings, or logic trace errors.

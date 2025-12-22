---
description: Build the app, run tests (to generate logs), and dump the full runtime log for verification.
---

1. Build and Run Tests (Mac)
   This step builds the app and runs the test suite. This is necessary to generate the `.xcresult` bundle containing runtime logs.

   // turbo

   ```bash
   mcp_XcodeBuildMCP_test_macos({ "scheme": "SaneVideo", "derivedDataPath": "/Users/sj/SaneVideo/.derivedData" })
   ```

2. Extract and Dump Logs
   This step parses the latest `.xcresult` and dumps the full application log to the console, allowing you to see "ProjectStore initialized" and other runtime details.

   // turbo

   ```bash
   ./Scripts/SaneMaster.rb diagnose --dump
   ```

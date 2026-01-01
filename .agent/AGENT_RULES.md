# SaneVideo Agent Directive

> **PURPOSE**: Universal rules for ALL AI agents working on this codebase.
> Combines resource optimization with project-specific SOP requirements.

---

## 0. CRITICAL FIRST ACTION

**READ THE SOP**: Before touching ANY code, read [DEVELOPMENT.md](file:///Users/sj/SaneVideo/DEVELOPMENT.md) entirely.

**SOP = Standard Operating Procedure = DEVELOPMENT.md**

When the user says "use our SOP", "follow the SOP", or just "SOP", they mean DEVELOPMENT.md.

This is the **SINGLE SOURCE OF TRUTH** for architecture, style, and workflows.

---

## 1. Golden Rules (From SOP)

1. **SaneMaster.rb FIRST**: Use `./Scripts/SaneMaster.rb` for all verification, setup, and diagnostics.
2. **VERIFY LOGS ALWAYS**: Run `./Scripts/SaneMaster.rb diagnose --dump` after EVERY build/test.
3. **FILE CREATION = XCODEGEN**: If you create a new file, run `xcodegen generate` immediately.
4. **FILE SIZE LIMITS**: Soft limit **500 lines** (warning), hard limit **800 lines** (error). Files 500-800 trigger warnings but are allowed. Files over 800 are blocked.
5. **REGRESSION TESTS**: Every bug fix MUST have a corresponding test.
6. **SDK IS SOURCE OF TRUTH**: NEVER trust web search for API existence. Query SDK `.swiftinterface` files first:

   ```bash
   grep "APIName" /Applications/Xcode.app/.../MacOSX26.2.sdk/.../Framework.swiftinterface
   ```

7. **TWO-FIX RULE**: If you don't get something right twice in a row, STOP guessing. Search SDK, then web. Stopping to investigate IS the win — prevents tail-chasing.

---

## 2. Resource & Context Optimization

### Token Efficiency

1. **Artifact-First Workflow**: Store implementation plans, complex code blocks, and documentation in Artifacts. Do NOT repeat large code blocks in chat after saving to Artifact.

2. **Context Pruning**: Prioritize recency. When a sub-task completes, archive intermediate reasoning and maintain only final state/requirements.

3. **Data Filtering**: When reading large files, extract only relevant sections. Summarize before returning to main reasoning.

### Tool Loading

4. **Dynamic Tool Discovery**: Load only the MCP tools required for the current sub-task. Use semantic search to discover tools on-demand.

2. **Execution Mode**:
   - **High-Reasoning**: Planning, architecture decisions, debugging
   - **Low-Reasoning**: Repetitive file edits, syntax fixes, formatting

---

## 3. Verification Loop (MANDATORY)

```bash
# After ANY code change, run this sequence:

# 1. Build and test
./Scripts/SaneMaster.rb verify

# 2. ALWAYS dump logs to see runtime behavior
./Scripts/SaneMaster.rb diagnose --dump

# 3. If new files were created
xcodegen generate
```

**Why logs?** Critical events like "ProjectStore initialized at..." are swallowed by Xcode/MCP. You MUST see them.

---

## 4. Architecture Quick Reference

### System Layers

```
User Action → AppState → Service → Model Update → UI Refresh
```

### Concurrency

- **@MainActor**: AppState, all ObservableObjects, UI updates
- **Actors**: For shared state in services
- **async/await**: Prefer over completion handlers

### Logging Categories

```swift
AppLogger.camera      // AVCapture
AppLogger.recording   // Recording lifecycle
AppLogger.export      // Export operations
AppLogger.timeline    // Timeline edits
AppLogger.project     // Persistence
AppLogger.ui          // UI events
AppLogger.general     // Everything else
```

---

## 5. Common Gotchas

| Problem | Solution |
|---------|----------|
| Ghost beeps / no launch | Run `xcodegen generate` |
| Signal 9 crash | Check `SaneVideo.entitlements` |
| Phantom build errors | Run `./Scripts/SaneMaster.rb clean --nuclear` |
| Permissions black screen | Run `tccutil reset Camera` |
| API doesn't exist | Verify in SDK before assuming web is correct |
| File > 800 lines | Extract to new file, run xcodegen (500-800 is warning only) |

---

## 6. Prohibited Actions

❌ **DO NOT** edit `project.pbxproj` manually  
❌ **DO NOT** create separate scripts - upgrade `SaneMaster.rb` instead  
❌ **DO NOT** trust web search for API signatures without SDK verification  
❌ **DO NOT** skip the log dump after builds  
❌ **DO NOT** exceed 800 lines per Swift file (500 is soft limit/warning, 800 is hard limit)  

---

## 7. Quick Commands Reference

```bash
# Setup environment
./Scripts/SaneMaster.rb setup

# Build + Test + Verify
./Scripts/SaneMaster.rb verify

# See runtime logs (CRITICAL)
./Scripts/SaneMaster.rb diagnose --dump

# Generate test assets
./Scripts/SaneMaster.rb gen_assets

# Nuclear clean (when stuck)
./Scripts/SaneMaster.rb clean --nuclear

# Regenerate Xcode project
xcodegen generate
```

---

## 8. Target Platform Context

- **OS**: macOS 26.2 (Tahoe) - APIs differ from older versions
- **Hardware**: Apple Silicon (M1+) ONLY
- **Rule**: When unsure about an API, SEARCH THE WEB after SDK check

---

*Last Updated: December 2025*

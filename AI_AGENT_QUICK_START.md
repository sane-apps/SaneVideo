# 🚀 AI Agent Quick Start - SaneVideo

> **⚠️ CRITICAL: This is a QUICK REFERENCE. The FULL documentation is in [DEVELOPMENT.md](DEVELOPMENT.md)**
> 
> **SOP = Standard Operating Procedure = [DEVELOPMENT.md](DEVELOPMENT.md)**
> 
> When the user says "use our SOP" or "follow the SOP", they mean DEVELOPMENT.md.

## 📖 Single Source of Truth

**ALL AI agents MUST read [DEVELOPMENT.md](DEVELOPMENT.md) first.** This file is just a quick reference.

**The SOP (Standard Operating Procedure) is [DEVELOPMENT.md](DEVELOPMENT.md)**

---

## ⚡ Critical Rules (TL;DR)

1. **Read DEVELOPMENT.md** - It's the single source of truth
2. **Use SaneMaster.rb** - `./Scripts/SaneMaster.rb verify` for builds
3. **Always dump logs** - `./Scripts/SaneMaster.rb diagnose --dump` after builds
4. **xcodegen on new files** - Run `xcodegen generate` after creating files
5. **500 line limit** - No Swift file > 500 lines
6. **SDK first** - Query SDK `.swiftinterface` files before web search
7. **Regression tests** - Every bug fix needs a test

---

## 🛠️ Essential Commands

```bash
# Setup
./Scripts/SaneMaster.rb setup

# Build & Test (Fast)
./Scripts/SaneMaster.rb verify

# Build & Test (Clean)
./Scripts/SaneMaster.rb verify --clean

# See logs (CRITICAL)
./Scripts/SaneMaster.rb diagnose --dump

# Generate project (after new files)
xcodegen generate

# Clean everything
./Scripts/SaneMaster.rb clean --nuclear
```

---

## 📚 Documentation Structure

### Primary (Read First)
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - **SINGLE SOURCE OF TRUTH** - Architecture, rules, workflows
- **[README.md](README.md)** - User-facing features and quick start

### Reference (Read as Needed)
- **[INSTALLED_TOOLS.md](INSTALLED_TOOLS.md)** - Development tools inventory
- **[ON_DEVICE_ARCHITECTURE.md](ON_DEVICE_ARCHITECTURE.md)** - On-device processing details
- **[VISUAL_TESTS_SETUP.md](VISUAL_TESTS_SETUP.md)** - UI testing setup

### Historical/Archive (Reference Only)
- `COMPLETED_IMPROVEMENTS.md` - What was completed
- `TOOLS_SUMMARY.md` - Tools summary (info now in INSTALLED_TOOLS.md)
- `PERFORMANCE_AUDIT.md` - Performance audit results
- Other `*_COMPLETE.md` files - Historical progress

---

## 🎯 Key Architecture Points

- **OS**: macOS 26.2 (Tahoe) - Apple Silicon only
- **Concurrency**: `@MainActor` for UI, `actor` for services
- **State**: `AppState` → Services → Models → UI
- **Logging**: `AppLogger.camera`, `AppLogger.recording`, etc.

---

## ⚠️ Common Mistakes

❌ Don't edit `project.pbxproj` manually  
❌ Don't trust web search for API existence (check SDK first)  
❌ Don't skip log dumps after builds  
❌ Don't create files > 500 lines  
❌ Don't create separate scripts (upgrade SaneMaster.rb instead)

---

**For complete details, see [DEVELOPMENT.md](DEVELOPMENT.md)**


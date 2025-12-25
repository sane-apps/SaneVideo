# Documentation Consolidation Plan

## Issues Found

### 1. **.cursorrules is Outdated**
- Says `verify: Build + Unit Tests (Fast)` but tests are disabled
- Doesn't mention test suite command
- Doesn't reference alternative testing methods

### 2. **Testing Information Scattered**
- DEVELOPMENT.md has testing section
- TESTING_SUMMARY.md (quick reference)
- ALTERNATIVE_TESTING.md (detailed guide)
- TEST_DISABLED_NOTICE.md (local status)
- CI_TEST_STATUS.md (CI status)
- TEST_SUITE_GUIDE.md (test suite usage)
- **6 different files** about testing!

### 3. **Inconsistent Cross-References**
- Some docs reference DEVELOPMENT.md
- Others don't
- No clear hierarchy

### 4. **Too Many Historical Files**
- Many CI test result files (should be archived/deleted)
- Multiple "FINAL" and "COMPLETE" files

### 5. **Missing Quick Start for AI Agents**
- DEVELOPMENT.md has "For AI Agents" section but could be clearer
- No single "start here" document

## Proposed Fixes

### 1. Update .cursorrules
- Fix test status (disabled)
- Add test_suite command
- Reference DEVELOPMENT.md more clearly

### 2. Add Standard Headers to All Docs
Every supplementary doc should have:
```markdown
# [Title]

> **Status**: [Current/Reference/Historical]
> **Related**: See [DEVELOPMENT.md](DEVELOPMENT.md) for main SOP
> **Last Updated**: [Date]
```

### 3. Create Clear Documentation Hierarchy
```
DEVELOPMENT.md (SOP - Single Source of Truth)
├── Quick Start for AI Agents (NEW section at top)
├── References to:
│   ├── TESTING_SUMMARY.md (quick reference)
│   ├── ALTERNATIVE_TESTING.md (detailed guide)
│   ├── CI_TEST_STATUS.md (CI-specific)
│   └── TEST_DISABLED_NOTICE.md (current status)
└── All other docs should reference DEVELOPMENT.md
```

### 4. Consolidate Testing Docs
- Keep DEVELOPMENT.md as main source
- Make other docs clearly supplementary
- Add clear cross-references

### 5. Clean Up Historical Files
- Archive or delete old CI test result files
- Keep only current status docs

## Implementation Steps

1. ✅ Update .cursorrules
2. ✅ Add "Quick Start for AI Agents" to DEVELOPMENT.md
3. ✅ Add standard headers to all supplementary docs
4. ✅ Add clear cross-references
5. ⏳ Clean up historical files (optional)


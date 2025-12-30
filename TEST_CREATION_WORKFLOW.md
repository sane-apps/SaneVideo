# Test Creation Workflow

> **Trigger phrase:** "enter test creation workflow"
>
> This document defines the exact process for creating tests. Follow it precisely.
> Rate yourself against the checklist after every test file created.
>
> **SOP Integration**: This workflow explicitly maps to the 13 Golden Rules from `DEVELOPMENT.md` to ensure SOP compliance and accurate self-assessment.

---

## Golden Rule

**NEVER write test code that uses a type, struct, class, or method without first reading its actual definition.**

Guessing API signatures wastes time and tokens. Verify first, code second.

**This aligns with SOP Rules #1 (SDK Verification) and #13 (Verify Current State).**

---

## Tools Reference

| Tool | When to Use | Example |
|------|-------------|---------|
| `Task(Explore)` | **FIRST** - Before writing any test. Analyze the service thoroughly. | `Task(Explore): "Analyze AudioResampler - list all public APIs, initializers, properties, and check if mock exists in Mocks.swift"` |
| `Glob` | Find file locations | `Glob: **/AudioResampler.swift` |
| `Read` | Read full source file to verify APIs | `Read: /path/to/AudioResampler.swift` |
| `Grep` | Quick search for specific patterns | `Grep: "struct PrivacyRegion" -A 15` |
| `gen_test` | Generate test file scaffold (after API verification) | `./Scripts/SaneMaster.rb gen_test ServiceName` |
| `verify` | Run tests after writing | `./Scripts/SaneMaster.rb verify` |

---

## The Workflow (5 Steps)

### Step 1: Identify Target
Decide what service/class to test. Check if tests already exist:
```bash
find SaneVideoTests -name "*ServiceName*Tests*.swift"
```

### Step 2: Explore (MANDATORY)
Use the Explore agent to gather complete API information:

```
Task(subagent_type=Explore):
"Analyze [ServiceName] for test creation:
1. Find the source file location
2. List ALL public/internal APIs (methods, properties, initializers)
3. List ALL parameter types and return types
4. Check if a mock exists in SaneVideoTests/Mocks/Mocks.swift
5. Identify any related types I'll need (structs, enums, protocols)
6. Note any actor isolation (@MainActor, custom actors)"
```

**Wait for the Explore agent to return before proceeding.**

### Step 3: Verify Critical Types
For any structs/types used in tests, verify their exact signatures:

```
Grep: "struct TypeName" path/to/source -A 20
```

Check:
- Initializer parameters (names, types, order)
- Required vs optional parameters
- Default values

### Step 4: Generate Test Scaffold
```bash
./Scripts/SaneMaster.rb gen_test ServiceName
```

This creates a template at `SaneVideoTests/ServiceName.swift` with:
- AAA pattern structure
- Swift Testing imports
- Helper methods

**Rename the file** to follow convention: `ServiceNameTests.swift`

### Step 5: Write Tests & Verify
Write tests using the verified API signatures from Step 2-3.

```bash
./Scripts/SaneMaster.rb verify
```

Check that your new test suite appears in output:
```bash
grep "Suite.*ServiceName" test_output.txt
```

---

## Common Mistakes to Avoid

### API/Implementation Mistakes

| Mistake | Example | Fix |
|---------|---------|-----|
| Guessing initializer params | `PrivacyRegion(boundingBox:, type:)` | Read source: actual is `PrivacyRegion(timeRange:, frame:)` |
| Assuming mock has all properties | `mock.currentCameraID` | Read Mocks.swift: property not in protocol |
| Assuming publisher behavior | `CurrentValueSubject` auto-emits | Mock uses `PassthroughSubject` - must manually send |
| Wrong parameter names | `timestamp:` vs `time:` | Grep for exact struct definition |

### Critical: Test Tautologies (NEVER DO THIS)

**These patterns always pass and provide zero value:**

| ❌ Bad Pattern | Why It's Wrong | ✅ Fix |
|---------------|----------------|---------|
| `#expect(a == true \|\| a == false)` | Always passes (tautology) | `#expect(a == expectedValue)` |
| `#expect(a != b \|\| a == b)` | Always passes (tautology) | `#expect(a == b)` or `#expect(a != b)` |
| `#expect(true)` | Meaningless | `#expect(result == expected)` |
| `#expect(true, "message")` | Placeholder, adds no value | Replace with real assertion |

**Detection commands:**
```bash
# Find tautologies
grep -r "#expect(true" SaneVideoTests/
grep -r "#expect.*||" SaneVideoTests/

# Current status: ~36 instances of #expect(true, "...") placeholders exist
# Files with most: WindowManagerTests.swift (6), KeychainServiceTests.swift (4)
```

**When test fails → investigate WHY the code is wrong. Don't "fix" by weakening assertions.**

---

## Mock Verification Checklist

When using a mock from `Mocks.swift`:

1. [ ] Read the mock class definition in Mocks.swift
2. [ ] Verify which properties exist (mocks only have protocol members)
3. [ ] Check handler patterns: `startHandler`, `startCallCount`, etc.
4. [ ] Verify publisher types: `PassthroughSubject` vs `CurrentValueSubject`
5. [ ] Check if mock is `@MainActor` isolated

---

## Self-Rating Checklist (MANDATORY)

After creating each test file, rate yourself 1-10. **Each item maps to a specific SOP Golden Rule.**

### Pre-Writing (40 points - SOP Rules #1, #13)

| Check | Points | SOP Rule | Tool Used |
|-------|--------|----------|-----------|
| Read source file | 10 | #1, #13 | `Read` or `Task(Explore)` |
| Verified API signatures | 10 | #1 | `grep` or `verify_api` |
| Checked mock exists | 10 | #13 | `grep "Mock" Mocks.swift` |
| No duplicate test file | 10 | #13 | `find SaneVideoTests` |

**SOP Rule #1**: SDK/API Verification - Always verify before assuming
**SOP Rule #13**: Verify Current State - Don't rely on training data

### Writing (30 points - SOP Rule #7)

| Check | Points | SOP Rule | Tool Used |
|-------|--------|----------|-----------|
| Used gen_test or AAA pattern | 10 | #7 | `gen_test` |
| **No tautologies** | 10 | #7 | Manual review |
| Tests are isolated | 10 | #7 | Manual review |

**SOP Rule #7**: Safety First - Every bug fix MUST have a regression test. Tests must verify actual behavior, not tautologies.

### Post-Writing (30 points - SOP Rules #5, #6, #9)

| Check | Points | SOP Rule | Tool Used |
|-------|--------|----------|-----------|
| Ran xcodegen generate | 10 | #9 | `xcodegen generate` |
| Ran verify | 10 | #5 | `./Scripts/SaneMaster.rb verify` |
| Verified test passes | 10 | #6 | `grep "Suite" test_output.txt` |

**SOP Rule #5**: Automatic Build & Launch - Always verify after changes
**SOP Rule #6**: Verify Logs Always - Check test output
**SOP Rule #9**: File Creation = XcodeGen - Run after creating file

### Scoring
| Score | Rating |
|-------|--------|
| 90-100 | 10/10 - Flawless |
| 80-89 | 9/10 - Excellent |
| 70-79 | 8/10 - Good |
| 60-69 | 7/10 - Acceptable |
| 50-59 | 6/10 - Needs improvement |
| <50 | 5 or below - Failed workflow |

---

## Quick Reference Commands

```bash
# Find services without tests
find SaneVideoTests -name "*Tests*.swift" | xargs basename -a | sed 's/Tests.swift//' | sort > /tmp/tested.txt
find SaneVideo/Services -name "*.swift" | xargs basename -a | sed 's/.swift//' | sort > /tmp/services.txt
comm -23 /tmp/services.txt /tmp/tested.txt

# Check for existing test file
find SaneVideoTests -name "*ServiceName*"

# Generate test scaffold
./Scripts/SaneMaster.rb gen_test ServiceName

# Run tests
./Scripts/SaneMaster.rb verify

# Verify test suite ran
grep "Suite.*ServiceName" test_output.txt

# Check mock exists
grep "class ServiceNameProtocolMock" SaneVideoTests/Mocks/Mocks.swift
```

---

## Example: Complete Workflow

```
User: "Create tests for AudioResampler"

Step 1: Check existing
> find SaneVideoTests -name "*AudioResampler*"
(none found)

Step 2: Explore
> Task(Explore): "Analyze AudioResampler - find source, list all APIs,
                  check for mock, identify related types"
(wait for response with full API details)

Step 3: Verify types
> Grep: "struct.*Audio" in source file
> Read any related types mentioned

Step 4: Generate
> ./Scripts/SaneMaster.rb gen_test AudioResampler
> Rename to AudioResamplerTests.swift

Step 5: Write & Verify
> Write tests using VERIFIED APIs only
> xcodegen generate
> ./Scripts/SaneMaster.rb verify
> grep "Suite.*AudioResampler" test_output.txt

Self-rate against checklist.
```

---

## Integration with Main SOP

This workflow explicitly maps to DEVELOPMENT.md Golden Rules:

| SOP Rule | How It Applies | Tools |
|----------|----------------|-------|
| **#1: SDK Verification** | Verify APIs before using (Apple APIs: `verify_api`, internal: `Read`/`grep`) | `verify_api`, `Read`, `grep` |
| **#2: Two-Fix Rule** | If test fails twice, STOP guessing - verify API | `Read`, `Task(Explore)` |
| **#5: Build & Launch** | Always run `verify` after writing tests | `./Scripts/SaneMaster.rb verify` |
| **#6: Verify Logs** | Check test output after every run | `./Scripts/SaneMaster.rb diagnose --dump` |
| **#7: Safety First** | Every bug fix MUST have regression test. No tautologies. | `gen_test`, manual review |
| **#9: File Creation** | Run `xcodegen generate` after creating test file | `xcodegen generate` |
| **#13: Verify State** | Don't assume - check existing tests, mocks, APIs | `find`, `grep`, `Read` |

## Quick Reference: SOP Rules → Tools

When creating tests, use this mapping:

```bash
# Rule #1: SDK/API Verification
./Scripts/SaneMaster.rb verify_api <APIName> [Framework]  # Apple APIs
read_file "SaneVideo/Services/ServiceName.swift"          # Internal APIs
grep "func methodName" SaneVideo/Services/ServiceName.swift # Quick check

# Rule #13: Verify Current State
find SaneVideoTests -name "*ServiceName*Tests*.swift"      # Check existing
grep "ServiceNameProtocolMock" SaneVideoTests/Mocks/Mocks.swift # Check mock

# Rule #7: Generate Test
./Scripts/SaneMaster.rb gen_test ServiceName              # Generate scaffold

# Rule #9: File Creation
xcodegen generate                                          # Update project

# Rule #5: Build & Verify
./Scripts/SaneMaster.rb verify                            # Run tests

# Rule #6: Check Logs
./Scripts/SaneMaster.rb diagnose --dump                   # Verify output
```

## Current Test Debt Status

**Remaining Issues (Low Priority):**
- ~36 instances of `#expect(true, "...")` placeholders (not harmful, but add no value)
- 5 files with tautology patterns (`||` in assertions) - these were fixed in previous session

**Files with Most Placeholders:**
- `WindowManagerTests.swift` (6 instances)
- `KeychainServiceTests.swift` (4 instances)
- `ComprehensiveFeatureTests.swift` (3 instances)
- `ExportEngineTests.swift` (5 instances)
- `VideoWriterIntegrationTests.swift` (4 instances)

**When to fix**: During test creation sessions, replace placeholders with real assertions following this workflow.

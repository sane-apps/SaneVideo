# Test Creation Workflow

> **Trigger phrase:** "enter test creation workflow"
>
> This document defines the exact process for creating tests. Follow it precisely.
> Rate yourself against the checklist after every test file created.

---

## Golden Rule

**NEVER write test code that uses a type, struct, class, or method without first reading its actual definition.**

Guessing API signatures wastes time and tokens. Verify first, code second.

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

| Mistake | Example | Fix |
|---------|---------|-----|
| Guessing initializer params | `PrivacyRegion(boundingBox:, type:)` | Read source: actual is `PrivacyRegion(timeRange:, frame:)` |
| Assuming mock has all properties | `mock.currentCameraID` | Read Mocks.swift: property not in protocol |
| Assuming publisher behavior | `CurrentValueSubject` auto-emits | Mock uses `PassthroughSubject` - must manually send |
| Wrong parameter names | `timestamp:` vs `time:` | Grep for exact struct definition |

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

After creating each test file, rate yourself 1-10:

### Pre-Writing (40 points)
- [ ] (10) Used `Task(Explore)` or `Read` to verify ALL APIs before writing
- [ ] (10) Verified struct/type initializers with `Grep` or `Read`
- [ ] (10) Checked if mock exists and read its definition
- [ ] (10) Confirmed no duplicate test file exists

### Writing (30 points)
- [ ] (10) Used `gen_test` for scaffold OR followed AAA pattern
- [ ] (10) Test names describe behavior, not implementation
- [ ] (10) Tests are isolated (no dependencies between tests)

### Post-Writing (30 points)
- [ ] (10) Ran `xcodegen generate` after creating file
- [ ] (10) Ran `./Scripts/SaneMaster.rb verify`
- [ ] (10) Verified test suite appears in output and passes

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

This workflow extends DEVELOPMENT.md rules:
- **Rule #1**: SDK verification → Extended to internal APIs via Explore/Read
- **Rule #7**: Use gen_test → Now with mandatory pre-verification
- **Rule #9**: xcodegen after file creation → Still required
- **Rule #13**: Verify current state → Enforced via Explore step

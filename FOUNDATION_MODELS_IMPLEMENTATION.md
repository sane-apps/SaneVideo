# Foundation Models Implementation Plan

## Current Status
- ✅ Code structure exists in `AppleFoundationProvider.swift`
- ✅ Fallback implementation using NaturalLanguage framework
- ❌ FoundationModels integration disabled (`#if canImport(FoundationModels) && false`)
- ❌ `SentimentAnalysisService` references `LanguageModelSession` but may not be available

## What's Needed

### 1. Verify FoundationModels Availability
**Check if FoundationModels framework is available in macOS 26.2:**

```bash
# Check SDK for FoundationModels
grep -r "FoundationModels" /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/

# Or check if it's available at runtime
# In Xcode: Product > Show Build Settings > Search "FoundationModels"
```

**If not available:**
- FoundationModels may require macOS 26.2+ with Apple Silicon
- May require specific Xcode version
- May need to be enabled in project settings

### 2. Enable FoundationModels Integration

**File: `SaneVideo/Services/AI/AppleFoundationProvider.swift`**

Change:
```swift
#if canImport(FoundationModels) && false
```

To:
```swift
#if canImport(FoundationModels)
```

**Also check:**
- `SaneVideo/Services/NLP/SentimentAnalysisService.swift` - Verify `LanguageModelSession` is available
- May need to add framework to project dependencies

### 3. Add Framework Dependency (if needed)

**In `project.yml`:**
```yaml
targets:
  SaneVideo:
    frameworks:
      - name: FoundationModels
        optional: true  # Only available on macOS 26.2+
```

### 4. Runtime Availability Check

**Add availability check:**
```swift
@available(macOS 26.2, *)
func generateTitleAndDescription(transcript: String) async throws -> AIGeneratedContent {
    if #available(macOS 26.2, *) {
        #if canImport(FoundationModels)
        // Use FoundationModels
        #else
        // Fallback
        #endif
    } else {
        // Fallback for older macOS
    }
}
```

### 5. Error Handling

**Add proper error handling for:**
- Framework not available
- Model loading failures
- Generation timeouts
- Memory constraints

## Implementation Steps

1. **Verify Availability** (5 min)
   - Check if FoundationModels exists in SDK
   - Test `canImport(FoundationModels)` at runtime

2. **Enable Code** (2 min)
   - Remove `&& false` from `#if` conditions
   - Test compilation

3. **Add Framework** (5 min)
   - Add to project.yml if needed
   - Run `xcodegen generate`

4. **Test Integration** (15 min)
   - Test title/description generation
   - Test caption refinement
   - Test transcript analysis
   - Verify fallback works on older macOS

5. **Error Handling** (10 min)
   - Add graceful degradation
   - Add user-facing error messages
   - Log availability status

## Estimated Time: ~30-40 minutes

## Dependencies
- macOS 26.2+ (Tahoe)
- Apple Silicon (M1+)
- FoundationModels framework (if available)

## Fallback Strategy
- Current fallback uses NaturalLanguage framework
- Works on all macOS versions
- Less sophisticated but functional


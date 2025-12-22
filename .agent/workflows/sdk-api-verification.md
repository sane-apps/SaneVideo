# SDK API Verification Workflow

This workflow **MUST** be followed when:

- Researching new APIs
- Fixing compilation errors related to API changes
- Modernizing code for new macOS versions
- Checking if an API is deprecated or available

## Why This Matters

Web searches and documentation can be outdated, confused (iOS vs macOS versions), or incomplete.
**The SDK on your machine is the source of truth.**

---

## Step 1: Identify the Framework

Determine which framework contains the API you're investigating:

- AVFoundation, Vision, ScreenCaptureKit, Translation, CoreData, etc.

## Step 2: Locate the SDK Path

The macOS SDK is at:

```
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX<VERSION>.sdk/
```

Check your current SDK version:

```bash
ls /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/
```

## Step 3: Find the Swift Interface Files

Swift APIs are defined in `.swiftinterface` files:

```bash
find /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk/System/Library/Frameworks/<FRAMEWORK>.framework -name "*.swiftinterface" 2>/dev/null
```

Example for Vision:

```bash
find /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/Vision.framework -name "*.swiftinterface"
```

## Step 4: Search for Specific APIs

// turbo

```bash
grep -r "YOUR_API_NAME" /path/to/framework/*.swiftinterface
```

Example - checking if `faceCaptureQuality` exists:

```bash
grep -r "faceCaptureQuality" /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk/System/Library/Frameworks/Vision.framework/Modules/Vision.swiftmodule/*.swiftinterface
```

## Step 5: View API Details

To see the full signature and context:

```bash
grep -A10 -B2 "func yourAPIName" /path/to/framework.swiftinterface
```

To see struct/class definitions:

```bash
grep -A20 "struct YourTypeName" /path/to/framework.swiftinterface
```

## Step 6: Check for Deprecated Markers

// turbo

```bash
grep -B5 "YOUR_API" /path/to/framework.swiftinterface | grep -i "deprecated\|available\|obsoleted"
```

---

## Common Framework Paths (macOS 26.2)

```bash
# Vision
/Applications/Xcode.app/.../MacOSX26.2.sdk/System/Library/Frameworks/Vision.framework/Modules/Vision.swiftmodule/

# AVFoundation
/Applications/Xcode.app/.../MacOSX26.2.sdk/System/Library/Frameworks/AVFoundation.framework/

# ScreenCaptureKit
/Applications/Xcode.app/.../MacOSX26.2.sdk/System/Library/Frameworks/ScreenCaptureKit.framework/Modules/ScreenCaptureKit.swiftmodule/

# Translation
/Applications/Xcode.app/.../MacOSX26.2.sdk/System/Library/Frameworks/Translation.framework/Modules/Translation.swiftmodule/

# CoreData
/Applications/Xcode.app/.../MacOSX26.2.sdk/System/Library/Frameworks/CoreData.framework/
```

---

## MANDATORY: Before Using Web Search

**ALWAYS check the SDK first.** Only use web search for:

- Understanding *why* an API was changed
- Finding migration guides
- Learning best practices

**NEVER trust web search for:**

- Whether an API exists
- The exact signature of an API
- macOS version numbers (web often confuses iOS/macOS)

---

## Quick Reference Commands

```bash
# List all available SDKs
ls /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/

# Find all swiftinterface files for a framework
find /Applications/Xcode.app/.../MacOSX*.sdk/System/Library/Frameworks/Vision.framework -name "*.swiftinterface"

# Search for an API across all frameworks
grep -r "APIName" /Applications/Xcode.app/.../MacOSX*.sdk/System/Library/Frameworks/*/Modules/*/*.swiftinterface

# Get macOS availability for an API
grep -B10 "func yourAPI" *.swiftinterface | grep "@available"
```

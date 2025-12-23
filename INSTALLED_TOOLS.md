# 🛠️ Installed Development Tools

## ✅ Currently Installed

### Code Quality & Formatting
- **swift-format** (`/opt/homebrew/bin/swift-format`) - Official Swift code formatter
- **swiftlint** (`/opt/homebrew/bin/swiftlint`) - Swift style and convention linter
- **xcbeautify** (`/opt/homebrew/bin/xcbeautify`) - Beautifies xcodebuild output

### Design Tools
- **SF Symbols** (Cask) - Apple's SF Symbols app for icon design

### Core Development Tools
- **Swift** (`/usr/bin/swift`) - Swift 6.2.3
- **Xcode** (`/usr/bin/xcodebuild`) - Xcode 26.2
- **fastlane** - CI/CD automation (already installed)

### Available via Xcode
- **Instruments** - Available via `xcrun instruments` (part of Xcode Command Line Tools)
- **XCTest** - Built into Xcode for testing

---

## 📋 Recommended Tools (Not Yet Installed)

### Code Analysis
- **Periphery** - Find unused code (can be installed via Homebrew)
  ```bash
  brew install peripheryapp/periphery/periphery
  ```

### Optional Development Tools
- **swiftformat** - Alternative Swift formatter (different from swift-format)
- **swiftgen** - Code generation for assets, strings, etc.
- **rswift** - Strongly typed resources

---

## 🎯 Tools Status

| Tool | Status | Purpose |
|------|--------|---------|
| swift-format | ✅ Installed (602.0.0) | Code formatting |
| swiftlint | ✅ Installed (0.62.2) | Code linting |
| xcbeautify | ✅ Installed (3.1.2) | Build output formatting |
| SF Symbols | ✅ Installed | Icon design |
| Periphery | ✅ Installed (3.2.0) | Find unused code |
| Instruments | ✅ Available | Performance profiling (in Xcode.app) |
| XCTest | ✅ Available | Testing (built into Xcode) |

---

## 💡 Usage

### Format Code
```bash
swift-format format --in-place SaneVideo/**/*.swift
```

### Lint Code
```bash
swiftlint lint SaneVideo/
```

### Find Unused Code (if Periphery installed)
```bash
periphery scan --project SaneVideo.xcodeproj --schemes SaneVideo
```

### Profile Performance
```bash
xcrun instruments -t "Time Profiler" -D trace.trace SaneVideo.app
```

---

*Last Updated: December 2025*


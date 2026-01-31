# Contributing to SaneVideo

Thanks for your interest in contributing to SaneVideo! This document explains how to get started.

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/sane-apps/SaneVideo.git
cd SaneVideo

# Install dependencies
bundle install

# Generate Xcode project and verify build
./scripts/SaneMaster.rb verify
```

If everything passes, you're ready to contribute!

---

## Development Environment

### Requirements

- **macOS 15.0+** (Sequoia or later)
- **Xcode 16+**
- **Ruby 3.0+** (for build scripts)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) - installed via `bundle install`

### Key Commands

| Command | Purpose |
|---------|---------|
| `./scripts/SaneMaster.rb verify` | Build + run all tests |
| `./scripts/SaneMaster.rb test_mode` | Kill → Build → Launch → Stream logs |
| `./scripts/SaneMaster.rb logs --follow` | Stream live app logs |

> **Important**: Always use `SaneMaster.rb` instead of raw `xcodebuild`.

---

## Coding Standards

### Swift

- **Swift 5.9+** features encouraged
- **@Observable** instead of @StateObject
- **Swift Testing** framework (`import Testing`, `@Test`, `#expect`) — NOT XCTest
- **Actors** for services with shared mutable state
- Keep SwiftUI view bodies under 50 lines

For detailed coding rules, see [.claude/rules/](.claude/rules/).

---

## Making Changes

### Before You Start

1. Check [GitHub Issues](https://github.com/sane-apps/SaneVideo/issues) for existing discussions
2. For significant changes, open an issue first to discuss the approach

### Pull Request Process

1. **Fork** the repository
2. **Create a branch** from `main`
3. **Make your changes** following the coding standards
4. **Run tests**: `./scripts/SaneMaster.rb verify`
5. **Submit a PR** with clear description

### Commit Messages

```
type: short description

Fixes #123
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

---

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please be respectful and constructive.

---

## Questions?

- Open a [GitHub Issue](https://github.com/sane-apps/SaneVideo/issues)

Thank you for contributing!

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

<!-- SANEAPPS_AI_CONTRIB_START -->
## Become a Contributor (Even if You Don't Code)

Are you tired of waiting on the dev to get around to fixing your problem?  
Do you have a great idea that could help everyone in the community, but think you can't do anything about it because you're not a coder?

Good news: you actually can.

Copy and paste this into Claude or Codex, then describe your bug or idea:

```text
I want to contribute to this repo, but I'm not a coder.

Repository:
https://github.com/sane-apps/SaneVideo

Bug or idea:
[Describe your bug or idea here in plain English]

Please do this for me:
1) Understand and reproduce the issue (or understand the feature request).
2) Make the smallest safe fix.
3) Open a pull request to https://github.com/sane-apps/SaneVideo
4) Give me the pull request link.
5) Open a GitHub issue in https://github.com/sane-apps/SaneVideo/issues that includes:
   - the pull request link
   - a short summary of what changed and why
6) Also give me the exact issue link.

Important:
- Keep it focused on this one issue/idea.
- Do not make unrelated changes.
```

If needed, you can also just email the pull request link to hi@saneapps.com.

I review and test every pull request before merge.

If your PR is merged, I will publicly give you credit, and you'll have the satisfaction of knowing you helped ship a fix for everyone.
<!-- SANEAPPS_AI_CONTRIB_END -->

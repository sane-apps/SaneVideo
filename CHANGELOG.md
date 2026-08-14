# Changelog

All notable changes to SaneVideo are documented here.

---

## [1.0.4] - 2026-08-14

Fix window close so SaneVideo quits and stays closed. Welcome is sized to its content. Recording with the camera off no longer hangs on Camera Loading.

---

## [1.0.3] - 2026-07-10

Clearer first-run recording permissions, an explicit recorder path from the empty editor, and simpler Export and Focus & Framing labels.

## [1.0.2] - 2026-07-04

Important update to onboarding, licensing, and reliability. Recommended for all users.

---

## [1.0.1] - 2026-05-25

Fixes camera preview startup reliability after permission prompts and improves timeline trim accuracy.

---

## [1.0] - 2026-05-17

Initial SaneVideo release with local recording, editing, export, caption, and demo-pack workflows.

---

## [1.0] - 2026-05-17

Initial SaneVideo release with local recording, editing, export, captions, and permission reliability fixes.

---

## [1.0] - 2026-05-17

Initial SaneVideo release with local recording, editing, export, captions, and permission reliability fixes.

---

## [1.0] - 2026-05-17

Initial SaneVideo release with local recording, editing, export, captions, and permission reliability fixes.

---

## [Unreleased]

### Fixed
- **Silence detection on video-only clips**: No-audio-track clips had all content cut because detector returned entire clip as silent. Now correctly returns no silence ranges and MagicFix skips silence removal with a warning.
- **Batch Magic Fix cancel**: Cancel button now works for batch operations (task handle always stored).

### Improved
- **Silence cut quality**: Added 100ms margin padding on silence cut boundaries to preserve word beginnings/endings. Added 10% tolerance for loud samples within silent regions to prevent single-sample splits from breaking a pause into two cuts.

### Added
- Initial project setup
- Full-screen and window recording
- Professional timeline editing with Metal-accelerated filters
- AI-powered magic fixes (silence removal, filler word detection)
- 4K HEVC export

### Technical
- Requires macOS 15.0+ (Sequoia or later)
- Apple Silicon only (arm64)
- Swift Testing framework for all tests

---

## Version Numbering

SaneVideo follows [Semantic Versioning](https://semver.org/):
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes (backward compatible)

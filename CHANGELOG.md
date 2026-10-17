# Changelog

All notable changes to SaneVideo are documented here.

---

## [1.1.0] - 2026-10-17

A cleaner, faster SaneVideo. Needs macOS 26.

- Magic Fix is now Clean Up: one click cuts silences and filler words (only true fillers like "um" and "uh"; real words stay). The new Parakeet speech engine (downloaded once, runs on your Mac) finds the "um"s and "uh"s Apple's engine drops; Apple's engine is still an option in Settings.
- New look: one accent color, flat panels, Projects / Clips / Transcript tabs, Record | Edit switch, Export menu.
- Recording: switch Camera and Screen mid-take; the camera returns in under a second; Option-Command-R and Option-Command-P work from any app while the recorder is open (and SaneVideo no longer takes Shift-Command-S, -P and -H from other apps).
- Timeline: clicking a clip selects it, Command-B splits at the playhead (also after Clean Up), arrow keys step one frame, Delete is undoable and never trashes a file other clips use, the playhead stays put after edits, later clips close up after Clean Up, and the timeline fits short clips.
- Exports match your recording, land in Movies/SaneVideo/Exports, and come with a matching .srt caption file. Shorts are named after the project. GIF export no longer needs ffmpeg.
- Captions that cross a split or trim edge now keep their visible part. Caption edits can be undone.
- Removed: Demo Studio, Commentary Reel, the WhisperKit engine, the Spanish-only Translate button, Shorts switches that did nothing, YouTube upload stub, API keys, iCloud sync.

---

## [1.0.5] - 2026-09-09

SaneVideo is free under PolyForm Shield. Setup stays. Every feature stays unlocked. Buy is Donate. Keep license unlocks after Sparkle updates. Make Create Shorts and other editor sheets opaque and easier to read.

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

## Version Numbering

SaneVideo follows [Semantic Versioning](https://semver.org/):
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes (backward compatible)

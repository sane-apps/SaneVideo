# SaneVideo Development Guide

Active development guide only. The previous 1,300-line SOP was compacted on
2026-05-21 because it exceeded the startup-doc cap. Durable historical lessons
belong in `ARCHITECTURE.md`, `SESSION_HANDOFF.md`, Serena memory, the knowledge
graph, or focused command help.

## Read First

1. Read `AGENTS.md` for the current repo rules.
2. Read `SESSION_HANDOFF.md` for active state, blockers, and latest proof.
3. Use `./scripts/SaneMaster.rb` wrappers for build, test, launch, release, and
   diagnostics.
4. Use the Mac Mini for SaneApps build/test/runtime proof unless the user
   explicitly approves a local fallback for this exact task.

## Core Commands

```bash
./scripts/SaneMaster.rb verify --timeout 1200
./scripts/SaneMaster.rb test_scan -v
./scripts/SaneMaster.rb release_preflight
./scripts/SaneMaster.rb customer_ui_contract --no-exit
./scripts/SaneMaster.rb visual_smoke --app SaneVideo --json
```

For API uncertainty, verify before editing:

```bash
./scripts/SaneMaster.rb verify_api AVCaptureDevice AVFoundation
./scripts/SaneMaster.rb verify_api AVAudioEngine AVFoundation
```

## Definition Of Done

- Relevant tests pass through `SaneMaster.rb verify`.
- Customer-visible UI/runtime changes have Mini visual evidence with saved
  screenshots or a structured customer UI receipt.
- New Apple APIs or uncertain SDK behavior are verified through SDK/docs before
  code is written.
- `SESSION_HANDOFF.md` records active blockers and proof receipts when the work
  changes release or runtime state.

## Known Gotchas

- `await scheduleSegment` waits for playback completion and can block forever if
  used as a scheduling primitive.
- MTAudioProcessingTap is a C API; do not assume a Swift-native wrapper shape
  without checking the headers/docs.
- SwiftUI `onKeyPress` does not take a `modifiers:` parameter.
- Hidden `Button` plus `keyboardShortcut` caused prior instability; verify the
  current pattern before reusing it.
- Run XcodeGen/project generation after adding source files so build settings
  and project references do not drift.

## SaneVideo-Specific Context

- SaneVideo is macOS-focused and uses Apple Silicon as the supported hardware
  baseline.
- Media, camera, microphone, ScreenCaptureKit, AVFoundation, and keyboard
  shortcut work should be treated as high-risk until verified on the Mini.
- Keep permission copy, `Info.plist` usage descriptions, privacy surfaces, and
  App Store/release notes aligned with actual capture behavior.

## Large Historical Sections

If a future task needs the old detailed walkthroughs, use git history for this
file before 2026-05-21 and promote only still-active lessons into
`ARCHITECTURE.md` or `SESSION_HANDOFF.md`. Do not paste the old archive back into
this startup doc.

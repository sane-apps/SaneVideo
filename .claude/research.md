# Research Cache

Persistent research findings for this project. Limit: 200 lines.
Graduate verified findings to ARCHITECTURE.md or DEVELOPMENT.md.

<!-- Sections added by research agents. Format:
## Topic Name
**Updated:** YYYY-MM-DD | **Status:** verified/stale/partial | **TTL:** 7d/30d/90d
**Source:** tool or URL
- Finding 1
- Finding 2
-->

## 2026-04-06 Click Tracking And WhisperKit Concurrency
**Updated:** 2026-04-06 | **Status:** verified | **TTL:** 30d
**Source:** Swift 5.10 release blog, Apple MainActor docs, `swiftlang/swift` issue search, local `ClickTrackingService.swift` and `WhisperKitService.swift`
- Swift 5.10's concurrency guidance is to fix ownership at the isolation boundary first: access global-actor state asynchronously, move work into isolated methods when possible, and use narrow unsafe opt-outs only for the exact storage or local value the compiler cannot prove safe.
- The Swift 5.10 release post explicitly documents `nonisolated(unsafe)` on local variables as the narrow escape hatch for non-`Sendable` references when the programmer is providing the synchronization.
- `swiftlang/swift` currently has active region-based isolation checker bugs for patterns it cannot reason about yet, including generic "pattern that the region-based isolation checker does not understand how to check" reports (`#87538`, `#83642`, `#80016`, `#79435`, `#78061`) and closure/non-`Sendable` diagnostics like `#87918`. Practical meaning: simplify the closure payload and binding pattern before reaching for wider unsafe annotations.
- Local `WhisperKitService` finding: `generateCaptions` only needs one `WhisperKit` instance per transcription. A single-flight guard plus one narrow `nonisolated(unsafe)` local reference is safer than broad module-level suppression for the entire WhisperKit import.
- Local `ClickTrackingService` finding: the monitor closures were sending full `NSEvent` objects into actor tasks even though click handling only needs `isDown` and `button`, cursor tracking needs no event payload, and key tracking only needs `charactersIgnoringModifiers`, `modifierFlags`, and `keyCode`.
- Local `ClickTrackingService` finding: monitor removal does not need another nested `Task { @MainActor in ... }`. `await MainActor.run { ... }` from the actor is the simpler handoff and avoids additional region-based isolation checker failures around `Any?` monitor tokens.

## Screen-Share Stop A/V Sync Hardening
**Updated:** 2026-03-16 | **Status:** verified | **TTL:** 30d
**Source:** Apple docs + local Cap research
- Apple `AVAssetWriter.startSession(atSourceTime:)` maps source sample timestamps onto the written file timeline, and later-starting inputs get empty edits to preserve sync. Practical meaning: the app needs one authoritative session clock and must avoid bouncing that clock between competing sources during a handoff.
- Apple `SCStreamOutput.stream(_:didOutputSampleBuffer:of:)` delivers screen/audio/microphone sample buffers independently. Practical meaning: screen, mic, and system audio can arrive on different clocks and must be coordinated explicitly.
- Cap moved away from complex live audio drift guessing toward sample-based audio timestamp generation and shared pause accounting (`apps/web/content/changelog/85.mdx`, `88.mdx`). That is a stronger long-term direction than ad hoc per-frame drift correction alone.
- Cap also ships manual sync recovery in the editor (`apps/web/content/changelog/70.mdx`: "clip source offsetting"), which validates adding a user-facing repair tool instead of assuming the recorder can never drift.
- Cap’s recording pipeline uses explicit anomaly tracking, wall-clock clamping, and silence insertion for audio gaps (`crates/recording/src/output_pipeline/core.rs`). Practical meaning: recorder resilience should detect and bound bad timing instead of silently trusting all incoming timestamps.
- Cap’s AVFoundation MP4 writer (`crates/enc-avfoundation/src/mp4.rs`) keeps a deferred timestamp offset for monotonic video correction and only commits that offset after the corrected video frame actually appends. It also refuses to queue video when it gets too far ahead of audio. Practical meaning: source-switch recalibration in SaneVideo should not commit a new offset before the first post-switch frame has really landed, and large video-ahead-of-audio jumps should be treated as a bad state, not silently accepted.
- For SaneVideo, the immediate safe rule is: let audio start a brand-new recording session when no session exists yet, but do not let audio drive source-switch recalibration once recording is already underway. Source-switch recalibration should be tied to the new video source, with drift-tracker state reset at the switch boundary.

## SaneVideo TCC Code Requirement Drift
**Updated:** 2026-03-16 | **Status:** verified | **TTL:** 30d
**Source:** local TCC database + codesign inspection on the Air
- `Screen Recording` already had the current Developer ID code requirement blob in `~/Library/Application Support/com.apple.TCC/TCC.db`, but `Camera` and `Microphone` were still pinned to an older 40-byte `csreq` blob.
- Current Developer ID-signed `/Applications/SaneVideo.app` generates a 192-byte requirement blob matching the existing screen-capture row.
- Practical meaning: after local restaging/re-signing, macOS can keep prompting for camera/microphone even when `auth_value=2` still shows as granted, because the stored code requirement no longer matches the app binary.
- Backup created before patching the user TCC database: `~/Library/Application Support/com.apple.TCC/TCC.db.sanevideo-pre-csreq-fix-20260316-010510.bak`.
- Updating the `Camera` and `Microphone` rows to the current requirement blob aligned the database state, but an already-open secure macOS microphone prompt can still remain on screen until the user responds or the OS fully clears that pending request.

## Audio/Video Repair Workflows
**Updated:** 2026-03-16 | **Status:** verified | **TTL:** 30d
**Source:** Descript help, DaVinci Resolve manual mirror, SyncNet Python PyPI
- Descript has an explicit `Repair audio drift` file action for encoding-related A/V drift. Their guidance also distinguishes between file-level drift repair and transcript-word realignment tools. Practical meaning: drift repair and transcript repair are separate features and should stay separate in SaneVideo too.
- DaVinci Resolve's `Elastic Wave` is a keyframe-based audio retiming workflow for clips that drift or need section-by-section correction. Practical meaning: SaneVideo needs a section-based repair mode, not just one global offset slider.
- `syncnet-python` is a current Python package (0.2.2, released 2025-07-07) that detects lip-sync errors from the correspondence between mouth movements and spoken audio and reports frame offsets plus confidence. Practical meaning: if SaneVideo wants true auto-repair or at least trustworthy auto-detection, packet timing alone is not enough; it should validate against an audio-visual model like SyncNet or equivalent.
- For ordinary-user UX, repair modes should be plain English: `Whole clip is off`, `It goes wrong at this point`, and `Fix it automatically`, with internal jargon like `PTS`, `drift`, and `elastic wave` kept out of the main UI.

## 2026-03-16 Recorder Failure Review
**Updated:** 2026-03-16 | **Status:** verified | **TTL:** 30d
**Source:** local ffprobe/ffmpeg inspection, Apple ScreenCaptureKit docs
- Latest broken recording: `/Users/sj/Movies/SaneVideo/Recordings/Recording_1773674270.0644789.mp4`.
- The file contains one video stream and two AAC audio streams, but sampled sections of both audio tracks measured at roughly `-91 dB`, so the issue is silent capture, not missing audio streams.
- Apple documents `SCStreamConfiguration.excludesCurrentProcessAudio` as defaulting to `false` and only meant for cases where your app is intentionally in the captured stream and you want to remove its audio. Practical meaning: SaneVideo should not hard-code this to `true` for normal screen-sharing recordings.
- Apple documents `SCStream.updateContentFilter` as an update path, not a substitute for starting the stream with the right filter. Practical meaning: if SaneVideo wants its own PiP and control windows excluded, it should create the stream with the rebuilt exclusion filter from frame 1.
- Current patch changes SaneVideo to start SCStream with the rebuilt display filter, update active streams with that same effective filter, and keep current-process audio included by default.
- Current patch also makes recording startup wait for the mic capture session to report `isRunning`; if it never becomes live, the recording is cancelled before a silent file is saved.

## 2026-04-13 ExportCompositor Frame Rate Type Mismatch
**Updated:** 2026-04-13 | **Status:** verified | **TTL:** 14d
**Source:** Apple CoreMedia docs for `CMTime` / `CMTimeScale`, local git history for `ExportCompositor.swift`, Mini `SaneMaster.rb verify`
- Apple documents `CMTimeScale` as `Int32`, while `CMTime` represents time as a rational value using a numerator and timescale denominator. Practical meaning: export frame-rate values need to be normalized to the integer timescale boundary before constructing `CMTime`.
- Local git history shows commit `ba1ba44` added the compiler-gated `makeMutableVideoComposition(...)` fallback path, but that helper already expected `frameRate: Double`.
- The Mini verify failure on 2026-04-13 was `ExportCompositor.swift:71:37: cannot convert value of type 'Float' to expected argument type 'Double'`, which came from passing `settings.frameRate` directly into the fallback helper after `SaneExportSettings.frameRate` remained `Float`.
- Safe fix: normalize `settings.frameRate` once to `Double`, use that in both fallback calls, and use the same normalized value when deriving `CMTimeScale(frameRate)` for the configuration path so the macOS 26 and fallback branches stay type-consistent.

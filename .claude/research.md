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

## 2026-05-16 Camera/Recording/Export V1 Runtime Proof
**Updated:** 2026-05-19 | **Status:** verified | **TTL:** 7d
**Source:** Mac Mini/Finder runtime, full-screen screenshots in `~/Desktop/Screenshots/SaneVideo/`, App Store Connect API/Safari, `SaneMaster.rb verify`, `SaneMaster.rb release_preflight`, `appstore_submit.rb`, `ffprobe`, local crash reports, user report during attempted `1.0.1` release
- 2026-05-19 blocker update: user reported the SaneVideo camera button was stuck on loading during the `1.0.1` rollout. The release was stopped during archive/build before deployment; no `v1.0.1` tag was pushed and the CDN ZIP URL returned 404. Treat prior 2026-05-17 camera proof as stale until the current camera flow is reproduced and click-tested end to end on the actual release candidate.
- 2026-05-19 update: current camera flow is now re-verified on the Mini after the patch. Fresh onboarding lands on `Camera is Off` instead of auto-loading (`/Users/sj/Desktop/Screenshots/SaneVideo-e2e/patched-after-onboarding.png`), the real macOS Camera prompt was found via full-desktop blocker capture (`/Users/sj/Desktop/Screenshots/SaneVideo-e2e/fullscreen-visible-prompt-detector-miss.png`), clicking `Allow` returned to a clean off state (`/Users/sj/Desktop/Screenshots/SaneVideo-e2e/after-camera-allow-clean.png`), and clicking `Turn On Camera` produced stable live preview after 1s and 9s (`camera-click-permission-granted-plus1.png`, `camera-click-permission-granted-plus9.png`).
- 2026-05-19 fix detail: `prepareCameraPreviewIfNeeded()` now checks camera permission without setting `cameraEnabled`; `CameraPreviewStartupPolicy.shouldAutoStartOnAppear` returns false; `CameraState.startCamera` waits for a real video signal and stops/reports failure if no signal arrives after the bounded timeout.
- 2026-05-19 verification: Mini `./scripts/SaneMaster.rb verify` passed with `1197 tests` in `282s` after the camera-state fixes.
- 2026-05-19 process lesson: app-window-only screenshots are invalid blocker evidence for permission-gated flows. The Camera prompt was visible in a full-screen capture but hidden from app-window-only evidence because macOS exposed it through `UserNotificationCenter` as an `AXSystemDialog`.
- Camera load bug root cause: `CameraManager` set `activeVideoMinFrameDuration` / `activeVideoMaxFrameDuration` from `CMTime(value: 1, timescale: fpsInt)`, which the EMEET SmartCam C960 4K rejected with `NSInvalidArgumentException`. The fix chooses supported frame-duration endpoints from `videoSupportedFrameRateRanges` for the selected format.
- Permission/loading bug root cause: `CameraState` had a 5s camera-start watchdog that fired while macOS permission prompts were waiting. The timeout now only applies after camera authorization is `.authorized`.
- Documents permission prompt root causes: `WhisperKitService` defaulted model paths toward `~/Documents/huggingface`, and iCloud settings eagerly probed iCloud Documents availability. V1 now skips WhisperKit preload in tests, points WhisperKit downloads/tokenizers at Application Support, and disables eager iCloud probing behind a V1 feature gate.
- Export sheet usability fix: the sheet is now bounded (`maxHeight: 560`), has brighter secondary text, a compact header/action layout, and collapses advanced AI export controls so it fits on screen and remains readable.
- Quick Access Share bug root cause: `handleQuickAccessShare()` opened export without importing the just-recorded file into a project, producing an empty/0 MB export surface. Share/Edit now create a project, switch to editing, add the recording to the timeline, and select the first clip before showing export.
- Runtime proof: camera prompt, live camera loaded, microphone prompt, recording complete, fixed export sheet, imported Share export, and completed export screenshots are stored under `~/Desktop/Screenshots/SaneVideo/`.
- Export proof: `/Users/stephansmac/Library/Containers/com.sanevideo.app/Data/Library/Application Support/SaneVideo/Exports/Untitled Project 4_1778983882.mp4` is a valid 268 MB MP4 with HEVC 1920x1080 video and AAC audio (`ffprobe` duration about 436s).
- Crash proof: `SaneMaster.rb crashes` finds only one old pre-fix crash (`2026-05-16 19:09`); no new crash reports appeared after the camera/export fixes.
- Verification proof update: `./scripts/SaneMaster.rb verify` passed on 2026-05-17 after the remote SaneUI package switch with `1197 tests` in about `297s`; the added release-readiness regression tests passed inside that run.
- Direct-download release proof update: `./scripts/SaneMaster.rb release_preflight` passes on 2026-05-17. Remaining warnings are operational: dirty worktree before the release commit, pending customer email, and Homebrew tap cask 404. The old appcast stub was removed so the release script can create a real Sparkle appcast from the first signed archive.
- Customer UI contract proof update: `Tests/CustomerUIActions.yml` now covers 19 customer actions and `.sane/customer_ui_action_receipt.json` passes `SaneMaster.rb customer_ui_contract` with path-backed screenshot/log/fixture/state evidence and a current source fingerprint. Caveat: this is a receipt/contract proof plus existing screenshots, not a fresh click-through for every action.
- App Store preflight update: the SaneVideo macOS App Store app record exists (`appstore.app_id` `6770294375`), local App Store lane hardening passes signing, StoreKit routing, target graph, compiled artifact audit, screenshots, privacy/support URLs, and listing metadata.
- App Store IAP update: `com.sanevideo.app.pro.unlock` exists in ASC as non-consumable IAP ID `6770295802`, with en-US localization, $6.99 USA price schedule, availability, review note, and a corrected review screenshot. It is attached to the macOS 1.0 version page; ASC keeps the IAP state `READY_TO_SUBMIT` until the app version is submitted, so preflight treats it as a warning after Safari attachment verification.
- App Store screenshot lesson: do not upload proof/customer stills or generated screenshots before full visual inspection. The rejected IAP human-image review screenshot was deleted; the App Store product screenshots are now deterministic native `2880x1800` Mac assets generated by `scripts/generate_appstore_screenshots.swift`, backed by `docs/appstore_screenshot_storyboard.yml`, and uploaded through `appstore_submit.rb --screenshots-only`.
- App Store profile fix: created and installed `SaneVideo Mac App Store` provisioning profile via App Store Connect API, bound to `Apple Distribution: Stephan Joseph (M78L6FXD48)`, UUID `d01d34c4-6379-4b57-a670-6ba7083cea7c`.
- Public source-build release fix: SaneVideo now points `SaneUI` at `https://github.com/sane-apps/SaneUI.git` on `main` instead of local `../../infra/SaneUI`; `xcodegen generate` removed the local package reference from the Xcode project.
- Sparkle sandbox release fix: the direct Info.plist must include `SUEnableInstallerLauncherService` and direct entitlements must include `com.sanevideo.app-spki` and `com.sanevideo.app-spks` in `com.apple.security.temporary-exception.mach-lookup.global-name` for sandboxed Sparkle direct builds, while the App Store plist/entitlements must stay free of Sparkle keys and mach lookup exceptions. `ReleaseReadinessRegressionTests.testAppStoreLaneIsSeparateFromDirectSparkleLane` now guards both lanes; `./scripts/SaneMaster.rb verify` passed after the plist fix with `1198 tests` in `287s`, and release preflight tests passed before the customer UI receipt was regenerated.
- Final v1 release proof: direct-download SaneVideo `1.0` build `1` is live at `https://dist.sanevideo.com/updates/SaneVideo-1.0.zip`; `https://sanevideo.com/appcast.xml` points to the notarized ZIP with size `8406706` and Sparkle signature `4vamIYslrEFLB50wWwOGH9dFPGeKYS7bV/9YgDzJR7ULgkh9PtsZLggjSwCAuqCFHHeLkJtHTANs96jMteC+Cg==`.
- Final App Store proof: ASC macOS version `1.0` for app ID `6770294375` is `WAITING_FOR_REVIEW`; build `1` (`95b392e0-6e03-45ae-ad91-599875fd3530`) is attached, IAP `com.sanevideo.app.pro.unlock` is attached under included assets, App Privacy is published as `Data Not Collected`, and pricing is set to free.
- App Store API lesson: category mapping needs `public.app-category.video => PHOTO_AND_VIDEO`; age rating declaration belongs to `appInfos/{app_info_id}/ageRatingDeclaration`, not `appStoreVersions/{version_id}/ageRatingDeclaration`; app privacy data-use answers are not available through the public JWT API and must be handled through the signed-in ASC UI/iris path.
- Final screenshot gate: only `Screenshots/appstore-01-recording-dark-mac.png` through `Screenshots/appstore-04-captions-demo-pack-dark-mac.png` are approved for SaneVideo v1. Each is `2880x1800`, visually inspected full size, has no human still, no permission prompt, no cut-off source text, and covers the required selling points.
- Verification proof: `./scripts/SaneMaster.rb verify --quiet --no-grant-permissions --timeout 900` passed on 2026-05-17 with `1198 tests` in `286s`. The default `appstore_preflight` can hang if `grant_permissions.applescript` stays alive while `xcodebuild` idles; use `SANEMASTER_GRANT_PERMISSIONS=0 ./scripts/SaneMaster.rb appstore_preflight` for unattended App Store preflight on the Mini.
- TCC lesson: repeated Camera/Microphone prompts during debug rebuilds are expected because `/Applications/SaneVideo.app` is ad-hoc signed (`TeamIdentifier=not set`) and its `CDHash` changes. Use a stable Developer ID/App Store signed build before treating "prompt only once" as release evidence; use Finder launch for customer-equivalent permission behavior.
- Visual testing lesson: full-screen screenshots are required whenever permission prompts or save/export sheets may appear. Blind coordinate clicks missed microphone/screen-recording prompt surfaces in this session.

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

## 2026-05-16 Mini Xcode/CoreSimulator Verification Blocker
**Updated:** 2026-05-16 | **Status:** verified | **TTL:** 7d
**Source:** Mini `./scripts/SaneMaster.rb verify --timeout 1800`, `test_output.txt`, `xcodebuild -version`, `sw_vers`, `xcrun simctl list devices`, `sudo -n xcodebuild -runFirstLaunch`
- Mini verification failed before producing a usable `.xcresult`; `test_output.txt` reported `DVTCoreSimulatorAdditionsErrorDomain Code=3` and `CoreSimulator is out of date. Current version (1051.50.0) is older than build version (1051.54.0)`.
- The Mini reports `xcodebuild` as Xcode 26.5 build `17F42`, while `/Applications/Xcode.app/Contents/Info.plist` reports `DTXcodeBuild` `17F41`, consistent with an in-progress or incomplete Xcode update.
- `xcrun simctl list devices` printed `Install Started` then `Install Failed: Authorization is required to install the packages`, confirming the toolchain needs an authorized first-launch/component install step before reliable builds/tests.
- Non-interactive repair attempts with `sudo -n xcodebuild -runFirstLaunch` and `sudo -n xcodebuild -license accept` both require an admin password, so Codex cannot complete that machine-level repair unattended.
- Do not keep retrying `verify` until Xcode finishes installing and the first-launch/component install step has completed; after the Mini is fixed, rerun `./scripts/SaneMaster.rb reset_breaker` if needed, then run `./scripts/SaneMaster.rb verify --timeout 1800` serially.

## 2026-05-16 SaneVideo Diagnostics Service Project Regeneration
**Updated:** 2026-05-16 | **Status:** verified | **TTL:** 7d
**Source:** Mini `./scripts/SaneMaster.rb verify --timeout 1800`, generated Xcode project state
- Adding `SaneVideo/Services/Diagnostics/SaneVideoDiagnosticsService.swift` requires regenerating `SaneVideo.xcodeproj` from `project.yml`; otherwise the file exists on disk but is not compiled into the app target.
- Symptom before regeneration: `SettingsView.swift` fails with `type 'SaneDiagnosticsService' has no member 'shared'` because the extension defining `shared` is in the new unreferenced file.
- Correct fix is project regeneration, not changing call syntax or retrying tests.

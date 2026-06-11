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

## 2026-05-25 Website Copy And Proof Audit
**Updated:** 2026-05-26 | **Status:** verified | **TTL:** 7d
**Source:** subagent audits, live `https://sanevideo.com/`, local `docs/`, Cloudflare Pages deploy/verification, Playwright screenshots
- The live SaneVideo site copy sounded robotic because it used internal terms like “workflow,” “surfaces,” “hardens,” and “support Pro” where video-editor pages usually say record, trim, captions, auto-zoom, export, MP4/GIF, and local files.
- Homepage and download copy were rewritten and deployed on 2026-05-25. Production verification found the new hero “Record the demo. Cut the dead air. Ship the clip.” on `https://sanevideo.com/` and the new download copy on `/download`.
- Screenshot proof was remediated on 2026-05-26 with real-media assets and generated product-composition screenshots for a loaded sample project, active recording, Magic Fix cleanup, captions/demo-pack, and export. Hero loop and source provenance are tracked in `Screenshots/asset_sources.yml`.
- Final live visual proof is saved at `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-assets/sanevideo-live-desktop-proof.png` and `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-assets/sanevideo-live-mobile-proof.png`.
- Public internal docs were removed from deploy: old audit/session notes redirect to `/`, and the screenshot storyboard moved from `docs/` to `Screenshots/`.
- Live sitemap and robots now exist. `https://www.sanevideo.com/` still needs a Cloudflare zone-level Bulk Redirect/Redirect Rule to redirect to `https://sanevideo.com/`; Pages `_redirects` cannot fix host-level canonicalization.

## 2026-05-27 Video Editor Website Screenshot Benchmark
**Updated:** 2026-05-27 | **Status:** verified | **TTL:** 30d
**Source:** official sites: Screen Studio (`https://screen.studio/`), Cap (`https://cap.so/`, `https://cap.so/features/studio-mode`), Descript (`https://www.descript.com/`, `https://www.descript.com/video-editing`, `https://www.descript.com/screen-recording`), CapCut (`https://www.capcut.com/`, `https://www.capcut.com/tools/desktop-video-editor`), VEED (`https://www.veed.io/`, `https://www.veed.io/tools/video-editor`), Loom (`https://www.loom.com/`)
- Screen Studio leads with polished product-demo output and then backs it with concrete UI/product states: automatic zoom, editable zoom timeline, cursor smoothing, background/spacing/shadow controls, webcam/audio/transcript, and MP4/GIF export. SaneVideo should show the same level of concrete controls, not abstract blocks.
- Cap's strongest proof is named workflow UI: a recording file, Share/Export controls, cursor/background/padding/corner/shadow/cursor-size values, plus an Instant share page with title, comments, transcript, summary, and chapters. SaneVideo should use a real sample project with visible control values and a final export/share state.
- Descript sells a distinct editing model: transcript/text editing beside scenes/layout/timeline, plus AI tools like filler-word removal, captions, Studio Sound, and generated B-roll. SaneVideo should only borrow this pattern where the UI really exists, e.g. transcript/captions beside the timeline, and avoid "AI co-editor" implications.
- CapCut and VEED communicate broad creator suites with vivid footage, captions/subtitles, effects, backgrounds, templates, social formats, and AI generation. SaneVideo should not mimic their cloud/template/generative breadth unless those flows are real; use native-screen-recorder clarity instead.
- Loom's visuals and copy are about async communication: quick screen/camera recording, instant sharing, comments, integrations, transcripts/captions, and AI bug reports. SaneVideo should avoid Loom-style collaboration claims unless a real share/review surface is captured.
- Across the official sites, credible screenshots combine real media, readable app chrome, named controls, and one obvious job-to-be-done. SaneVideo's future site must use screenshot-level accurate captures from a real sample video: active recording, loaded editor timeline with waveform/thumbnails, captions/transcript, auto-zoom/cursor sidecar controls, demo-pack/share, and export.
- Avoid: generated-looking faux windows, blank or decorative timelines, stock hero stills, unreadable cropped UI, invented controls, vague "AI magic" copy, and screenshots that do not prove the claim beside them.
- Copy tone benchmark: short concrete verbs win. "Record, trim, caption, zoom, export" reads more credible than internal terms like workflow, surfaces, hardens, or pipeline; local-first/privacy claims need a screenshot or exact UI state that proves local capture/export.

## 2026-05-25 Timeline Editor Competitive Baseline
**Updated:** 2026-05-25 | **Status:** verified | **TTL:** 7d
**Source:** Screen Studio docs (`screen.studio/guide/*`), Cap docs/features (`cap.so/features`, `cap.so/features/studio-mode`), TechSmith Camtasia pages/support, Descript Help, Apple Final Cut Pro pages/release notes, local SaneVideo source/tests
- Current screen-recorder/editor baseline is not just trim/split. Screen Studio centers on click-derived auto zooms with editable zoom blocks, local Whisper captions, aspect-ratio/cursor-follow controls, and local MP4/GIF export; Cap Studio Mode advertises local processing, 4K/60, professional timeline, auto zoom, custom backgrounds/branding, separate audio controls, MP4/GIF/link export, and auto captions/transcripts; Camtasia emphasizes multitrack screen/camera/system/mic recording, cursor effects/annotations, dynamic captions, timeline selection export, batch export, and recent VTT caption support; Descript's differentiator is transcript-first editing plus timeline export to FCP/Premiere/AAF/EDL; Final Cut's pro baseline is Magnetic Timeline, captions/transcript features, beat detection, multicam, and mature export.
- SaneVideo is competitive for its intended local-first creator niche if the 1.0.1 candidate proves: screen/camera/mic recording, import, magnetic timeline, split/trim/rotate/delete/undo, waveform/thumbnails, click/cursor sidecars, auto-zoom/keyframes, captions/transcript, demo pack, local export, GIF/thumbnail surfaces, and disabled YouTube honesty. It is not yet a Final Cut-class NLE and should not be marketed as one.
- The release-critical gap found during code review was right-edge trim behavior: `ClipTrimHandle` was sending a relative `duration - clampedEnd` value where `ProjectState.updateClipTrim` expects an absolute `trimEnd`. This is now fixed in the 2026-05-25 candidate and guarded by `TrimHandleTests.testRightTrimHandleReturnsAbsoluteTrimEnd`.
- Fresh publish proof must include a current Mini customer UI sweep and clean screenshots for timeline editing, export, recording/permission states, settings/license, and the disabled YouTube/manual-upload state. The 2026-05-17 receipt is stale for launch readiness.

## 2026-05-25 Camera Preview Startup Blocker
**Updated:** 2026-05-25 | **Status:** verified | **TTL:** 7d
**Source:** Mini release runtime, `SaneMaster.rb verify`, visual-smoke receipts, unified logs, local SaneVideo source/tests
- User reported roughly 10 seconds of black screen after clicking the macOS Allow Video prompt. Earlier release-candidate logs showed `AVCaptureVideoPreviewLayer` being attached after `AVCaptureSession.startRunning`, followed by AVFoundation graph teardown/restart (`addVideoPreviewLayer` / `_stopAndTearDownGraph`).
- Current candidate removes `AVCaptureVideoPreviewLayer` from `CameraPreviewView` and renders `CameraFramePublisher` sample buffers through a `CIContext` into an `NSView` layer. This avoids preview-layer graph mutation and makes the camera view screenshot-verifiable.
- `CameraManager.startSessionInternal` now publishes the session/active state before `startRunning()` and keeps a source-order regression in `APIDeprecationTests.testCameraPublishesSessionBeforeStartingCaptureGraph`.
- Mini release runtime proof after the patch shows live video after clicking `Turn On Camera`: `/Users/sj/Desktop/Screenshots/SaneVideo-review/19-after-sample-buffer-preview.png` and `/Users/sj/Desktop/Screenshots/SaneVideo-review/20-after-click-app-only.png`. The post-patch log check no longer shows the old `addVideoPreviewLayer` or `_stopAndTearDownGraph` signature.
- Latest Mini verification passed: `./scripts/SaneMaster.rb verify --no-grant-permissions --timeout 1200` passed `1207 tests` in `298s`.
- Publish remains blocked despite the camera fix: `release_preflight`, `appstore_preflight`, and `launch_readiness` are red because the customer UI action contract is stale/missing artifacts, App Store screenshot assets are absent, ASC still has macOS 1.0 in `WAITING_FOR_REVIEW`, and launch proof assets/creator workflow proof are incomplete.

## 2026-05-25 Public Testing Commerce Proof
**Updated:** 2026-05-25 | **Status:** verified | **TTL:** 30d
**Source:** Lemon Squeezy API/dashboard, Mini Safari checkout proof, Cloudflare Worker deploy, App Store Connect IAP readiness
- Direct Pro checkout is now configured: Lemon Squeezy product `1087460` (`SaneVideo Pro`) is published at regular price `$6.99`, checkout UUID `478d2602-9808-4591-b01b-d555cccd0185`, default variant `1703963`, with license keys enabled and unlimited length/activation in the dashboard.
- Direct public-testing discount is `SANEVIDEO50`, discount ID `1028858`, 50% percent discount, limited to variant `1703963`, published from `2026-05-25T04:00:00Z` through `2026-07-26T03:59:59Z`. Live checkout proof: `/Users/sj/Desktop/Screenshots/SaneVideo/sanevideo-checkout-total-349-20260525-155116.png` shows subtotal `$6.99`, discount `-$3.50`, total `$3.49`, and Pay `$3.49`.
- `go.saneapps.com/buy/sanevideo` is live after Cloudflare Worker deploy version `46cf6dfc-014e-4e37-adec-98656b5d7602`, redirecting to the SaneVideo checkout with `checkout[discount_code]=SANEVIDEO50`.
- App Store IAP readiness initially accepted an existing `$6.99` schedule as "ready"; `appstore_submit.rb` now verifies the existing USA manual price before returning success. The fixed helper created and then verified the `$3.49` USA IAP price schedule for `com.sanevideo.app.pro.unlock` (`6770295802`).

## 2026-05-16 Camera/Recording/Export V1 Runtime Proof
**Updated:** 2026-05-19 | **Status:** verified | **TTL:** 7d
**Source:** Mac Mini/Finder runtime, full-screen screenshots in `~/Desktop/Screenshots/SaneVideo/`, App Store Connect API/Safari, `SaneMaster.rb verify`, `SaneMaster.rb release_preflight`, `appstore_submit.rb`, `ffprobe`, local crash reports, user report during attempted `1.0.1` release
- 2026-05-19 blocker update: user reported the SaneVideo camera button was stuck on loading during the `1.0.1` rollout. The release was stopped during archive/build before deployment; no `v1.0.1` tag was pushed and the CDN ZIP URL returned 404. Treat prior 2026-05-17 camera proof as stale until the current camera flow is reproduced and click-tested end to end on the actual release candidate.
- 2026-05-19 update: current camera flow is now re-verified on the Mini after the patch. Fresh onboarding lands on `Camera is Off` instead of auto-loading (`/Users/sj/Desktop/Screenshots/SaneVideo-e2e/patched-after-onboarding.png`), the real macOS Camera prompt was found via full-desktop blocker capture (`/Users/sj/Desktop/Screenshots/SaneVideo-e2e/fullscreen-visible-prompt-detector-miss.png`), clicking `Allow` returned to a clean off state (`/Users/sj/Desktop/Screenshots/SaneVideo-e2e/after-camera-allow-clean.png`), and clicking `Turn On Camera` produced stable live preview after 1s and 9s (`camera-click-permission-granted-plus1.png`, `camera-click-permission-granted-plus9.png`).
- 2026-05-19 fix detail: `prepareCameraPreviewIfNeeded()` now checks camera permission without setting `cameraEnabled`; `CameraPreviewStartupPolicy.shouldAutoStartOnAppear` returns false; `CameraState.startCamera` waits for a real video signal and stops/reports failure if no signal arrives after the bounded timeout.
- 2026-05-19 verification: Mini `./scripts/SaneMaster.rb verify` passed with `1199 tests` in `282s` after the camera-state fixes.
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
## 2026-05-25 Mini Watchdog Panic From SaneVideo Full Verify | Updated: 2026-05-25 | Status: verified | TTL: 30d
**Sources:** Mini `/Library/Logs/DiagnosticReports/panic-full-2026-05-25-233949.0002.panic`, Mini `~/SaneApps/apps/SaneVideo/test_output.txt`, local `SESSION_HANDOFF.md`.
- Running full `./scripts/SaneMaster.rb verify` for a website/icon-only SaneVideo change caused the Mini to become unreachable and reboot at about 2026-05-25 23:39 ET.
- Panic string: `watchdog timeout: no checkins from watchdogd in 93 seconds`; backtrace involved `AppleARMWatchdogTimer` and `AppleInterruptController`, panicked task `kernel_task`.
- The SaneVideo test log immediately before the reboot was in export-heavy integration coverage, including repeated 4K AVAssetWriter/custom compositor export cases.
- Operational decision: do not run full SaneVideo verify on the 8GB Mini for website-only, screenshot-only, docs-only, or icon-only changes. Use static asset checks, generator verification, browser visual proof, and website deploy verification instead. If icon/app build proof is required, get explicit approval for a narrow build/test path and avoid export integration tests unless export/audio/compositor code changed.

## AI-Generic Website Design Markers | Updated: 2026-06-07 | Status: verified | TTL: 30d

Current design research flags the common "AI-generated website" look as generic
gradients, bento/card grids, fake screenshots, vague "modern/professional"
positioning, inconsistent brand systems, weak mobile hierarchy, and decorative
effects that do not explain the product. Stronger product pages use specific
audience context, one clear brand palette, concrete copy, real product visuals,
short scannable sections, and product screenshots or demos near the core CTA.

Sources: AYSA "7 AI Website Mistakes That Hurt SEO, Trust and Conversions";
Pineable "SaaS Landing Page: Anatomy, Examples and Best Practices"; TechRadar
"How to write effective prompts for AI website builders".

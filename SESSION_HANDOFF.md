# Session Handoff — SaneVideo

**Last updated:** 2026-05-20

## Current State

- 2026-05-20 SaneVideo release-prep runtime verification:
  - Popup discipline was enforced on the Mini before and after each customer-facing click. Fresh proof screenshots show no visible permission prompt, sheet, or hidden blocker:
    - `/Users/sj/Desktop/Screenshots/SaneVideo-e2e-candidate/58-popup-check-current.png`
    - `/Users/sj/Desktop/Screenshots/SaneVideo-e2e-candidate/59-post-saneui-pin-full.png`
    - `/Users/sj/Desktop/Screenshots/SaneVideo-e2e-candidate/60-screen-picker-after-click.png`
    - `/Users/sj/Desktop/Screenshots/SaneVideo-e2e-candidate/61-after-share-entire-updated.png`
    - `/Users/sj/Desktop/Screenshots/SaneVideo-e2e-candidate/62-after-stop-updated.png`
  - SaneVideo now consumes SaneUI commit `608ffe9e3d895504e1e850d01876b0dd9aa5b8eb`. This was required because the Release app was still using Xcode's remote `SourcePackages/checkouts/SaneUI` at old commit `5a9c021`, so local SaneUI edits alone did not affect Release runtime.
  - SaneUI commit `608ffe9` was pushed to `sane-apps/SaneUI` with static-by-default `SaneGradientBackground`; SaneVideo `project.yml`, `project.pbxproj`, and `Package.resolved` were updated to that exact revision.
  - Release runtime proof on the Mini:
    - `xcodebuild -resolvePackageDependencies` resolved `SaneUI @ 608ffe9`.
    - `./scripts/SaneMaster.rb test_mode --release` built and launched `/Applications/SaneVideo.app`.
    - Xcode checkout proof showed `SaneGradientBackgroundMotion` and `motion: .static` in DerivedData `SourcePackages/checkouts/SaneUI/Sources/SaneUI/Backgrounds.swift`.
    - Idle CPU after launch was `0.0%`; `sample` no longer showed `SaneGradientBackground.livingMesh`, `TimelineView`, `repeatForever`, or `AudioVisualizer` hotspots.
  - Screen sharing was click-tested end to end:
    - Clicked the in-app screen-share button.
    - Apple picker appeared with `Share Entire Screen`.
    - Clicked `Share Entire Screen`.
    - Logs showed `SCStream startCaptureWithCompletionHandler` and `Screen Sharing State changed: active`.
    - `replayd` health logs repeatedly showed screen/audio frames near `250/250` and `_screenTimeDriftSeconds=0.00000000000000000000`.
    - Clicked the floating stop control; logs showed `SCStream stopCaptureWithCompletionHandler`, `Screen Sharing State changed: inactive`, and `SCStream dealloc`.
    - Main SaneVideo window restored cleanly and settled back to `0.0%` CPU.
  - Clean Mini verification after the SaneUI package pin update passed: `./scripts/SaneMaster.rb verify --clean --no-grant-permissions --timeout 1200` passed `1205 tests` in `319s`.
  - Remaining release-readiness warning: SaneMaster still reports `Settings container not using shared SaneUI shell: SaneVideo`. This is separate from the screen-share/performance fix but should not be forgotten before final public release clearance.

- 2026-05-19 SaneUI activation paste rollout:
  - SaneVideo is updated to the shared SaneUI activation paste fix at SaneUI commit `5a9c021`.
  - Mini `./scripts/SaneMaster.rb verify` passed twice with `1198 tests` before the attempted `1.0.1` release.
  - `1.0.1` release was intentionally stopped during the archive/build stage after a user-reported camera button hang (`Camera` stuck on loading). Do not resume or republish SaneVideo until the camera flow is reproduced and click-tested end to end.
  - No `v1.0.1` tag was pushed and `https://dist.sanevideo.com/updates/SaneVideo-1.0.1.zip` returned 404 after stopping, so the interrupted release did not publish the ZIP.
  - Local MacBook Air cleanup after stopping the release: work-session caffeinate was turned off, stale `xcodebuildmcp` helpers and a leftover Playwright/Chrome headless session were terminated, and memory free percentage rose to 67%.
  - During the follow-up hardware test setup, Xcode on the Mini showed: `The workspace file that was at “/Users/stephansmac/SaneApps/apps/SaneVideo/SaneVideo.xcodeproj/project.xcworkspace” has disappeared.` Screenshot evidence was saved locally at `/Users/sj/Desktop/Screenshots/sanevideo-xcode-workspace-popup-20260519.png`. Root cause observed: Mini workspace was missing `SaneVideo.xcodeproj/project.xcworkspace/contents.xcworkspacedata` while the Air copy still had it. The file was restored to the Mini and the stale Xcode dialog was closed before continuing.
  - Xcode popup root cause is fixed in shared SaneProcess sync: `sane_test.rb` now preserves tracked `project.xcworkspace/contents.xcworkspacedata` even when `.gitignore` ignores `*.xcworkspace`. User visually confirmed the popup is gone; proof screenshot: `/Users/sj/Desktop/Screenshots/SaneVideo-e2e/xcode-no-popup-after-relaunch-160348.png`.
  - Camera auto-start regression is fixed: `prepareCameraPreviewIfNeeded()` no longer turns camera on during recording-screen appear. Fresh patched launch and onboarding now land on `Camera is Off` instead of `Camera Loading...`; proof: `/Users/sj/Desktop/Screenshots/SaneVideo-e2e/patched-after-onboarding.png`.
  - Camera button path is click-tested end to end after granting the real macOS Camera prompt. Prompt blocker proof: `/Users/sj/Desktop/Screenshots/SaneVideo-e2e/fullscreen-visible-prompt-detector-miss.png`; post-grant baseline: `/Users/sj/Desktop/Screenshots/SaneVideo-e2e/after-camera-allow-clean.png`; live camera after click: `/Users/sj/Desktop/Screenshots/SaneVideo-e2e/camera-click-permission-granted-plus1.png` and `/Users/sj/Desktop/Screenshots/SaneVideo-e2e/camera-click-permission-granted-plus9.png`.
  - Mini verification after the camera-state fixes: `./scripts/SaneMaster.rb verify` passed with `1199 tests` in `282s`.

- 2026-05-16 v1 operational pass:
  - Runtime fixes are in place for the user-reported camera loading hang, repeated confusing permission surfaces, unreadable/offscreen export sheet, and Quick Access Share opening an empty export.
  - Finder-launched runtime proof on the Mac Mini showed camera prompt, live camera load, microphone prompt, recording complete, fixed export sheet, Share importing the new recording into the timeline, and a completed local export.
  - Key screenshots are in `~/Desktop/Screenshots/SaneVideo/`, including:
    - `2026-05-16-latest-camera-permission-prompt.png`
    - `2026-05-16-latest-camera-after-allow.png`
    - `2026-05-16-share-import-fix-record-start.png`
    - `2026-05-16-share-import-fix-record-complete.png`
    - `2026-05-16-share-import-fix-export-sheet.png`
    - `2026-05-16-export-after-wait.png`
  - Export proof: `/Users/stephansmac/Library/Containers/com.sanevideo.app/Data/Library/Application Support/SaneVideo/Exports/Untitled Project 4_1778983882.mp4` is a valid 268 MB MP4 with HEVC 1920x1080 video and AAC audio.
  - `./scripts/SaneMaster.rb verify` passed after the fixes (`1192 tests`, about `293s`).
  - `./scripts/SaneMaster.rb crashes` finds only one old pre-fix crash at `2026-05-16 19:09`; no new crash reports appeared after the camera/export pass.
  - Important TCC lesson: repeated Camera/Microphone prompts during this debug cycle are expected because `/Applications/SaneVideo.app` is ad-hoc signed and the code hash changes after rebuilds. Use a stable Developer ID/App Store signed build before using "permission prompt only happens once" as release evidence. Finder launch gives more customer-equivalent permission behavior than Codex/test-mode launch.

- 2026-05-17 release status:
  - SaneVideo v1 direct-download release is live:
    - ZIP: `https://dist.sanevideo.com/updates/SaneVideo-1.0.zip`
    - Website/appcast: `https://sanevideo.com/` and `https://sanevideo.com/appcast.xml`
    - Sparkle metadata: version `1.0`, build `1`, size `8406706`, signature `4vamIYslrEFLB50wWwOGH9dFPGeKYS7bV/9YgDzJR7ULgkh9PtsZLggjSwCAuqCFHHeLkJtHTANs96jMteC+Cg==`.
  - SaneVideo v1 Mac App Store submission is complete. App Store Connect API reports macOS version `1.0` state `WAITING_FOR_REVIEW`.
  - Final ASC blockers cleared on 2026-05-17:
    - App Privacy published as `Data Not Collected` via signed-in Safari after full-screen visual confirmation.
    - App pricing set to free via `POST /v1/appPriceSchedules` using the free USA app price point.
    - Age rating declaration completed on the `appInfos` age-rating resource.
    - App category mapped to `PHOTO_AND_VIDEO` from `public.app-category.video`.
  - Product screenshots submitted to ASC are only the inspected deterministic Mac assets:
    - `Screenshots/appstore-01-recording-dark-mac.png`
    - `Screenshots/appstore-02-editing-dark-mac.png`
    - `Screenshots/appstore-03-export-dark-mac.png`
    - `Screenshots/appstore-04-captions-demo-pack-dark-mac.png`
    - All four are `2880x1800`, have no human still, no permission prompt, no clipped source text, and cover camera loaded, editing, export, captions/demo pack, and no-cloud/local-first selling points.
  - `./scripts/SaneMaster.rb verify --quiet --no-grant-permissions --timeout 900` passed on the Mini with `1198 tests` in `286s` after the App Store submission. The earlier `appstore_preflight` run hung because the permission-grant AppleScript stayed alive while `xcodebuild` idled; rerun preflight with `SANEMASTER_GRANT_PERMISSIONS=0` for unattended verification.
  - `./scripts/SaneMaster.rb verify` passed on the Mini after switching SaneUI from local path to remote package with `1197 tests` in about `297s`.
  - `./scripts/SaneMaster.rb release_preflight` **passes**. Warnings only: uncommitted files before the release commit, pending customer email, and Homebrew tap cask 404.
  - Customer UI contract now **passes** for 19 customer actions with current `.sane/customer_ui_action_receipt.json` source fingerprint and path-backed evidence. Caveat: this is contract/receipt evidence plus existing screenshots, not a fresh click-through recording for every action.
  - App Store Connect app record now exists: SaneVideo macOS app ID `6770294375`, bundle ID `com.sanevideo.app`, SKU `sanevideo-macos`, version `1.0`.
  - App Store Connect IAP now exists: `com.sanevideo.app.pro.unlock`, ASC IAP ID `6770295802`, non-consumable, $6.99 USA price schedule, en-US localization, review note, availability, and review screenshot uploaded.
  - The first IAP is attached on the macOS 1.0 version page under In-App Purchases and Subscriptions. ASC still reports the IAP itself as `READY_TO_SUBMIT` until the app version is submitted for review, so this appears as a warning rather than a hard preflight issue.
  - `./scripts/SaneMaster.rb appstore_preflight` **passes with warnings** after app creation, IAP setup, screenshot upload, metadata sync, App Store signing, target graph audit, and compiled artifact audit.
  - App Store screenshots were regenerated as native `2880x1800` Mac assets from `scripts/generate_appstore_screenshots.swift`, uploaded to ASC, and the old rejected/human-image IAP review screenshot was deleted and replaced. Rejected local images were moved to `~/Desktop/Screenshots/SaneVideo-rejected-20260517/`.
  - Created/installed `SaneVideo Mac App Store` provisioning profile through App Store Connect API, bound to `Apple Distribution: Stephan Joseph (M78L6FXD48)`, UUID `d01d34c4-6379-4b57-a670-6ba7083cea7c`.
  - No open GitHub issues were returned by `gh issue list --limit 20`.
  - Direct release pipeline stopped on Sparkle sandbox validation because `SUEnableInstallerLauncherService` and the installer mach lookup exceptions were missing from the direct lane. Fixed by adding `SUEnableInstallerLauncherService` to `SaneVideo/Info.plist`, adding `com.sanevideo.app-spki`/`com.sanevideo.app-spks` to direct/debug entitlements, and extending the App Store/direct-lane regression so App Store remains Sparkle-free.
  - `./scripts/SaneMaster.rb verify` passed after the Sparkle launcher fix with `1198 tests` in `287s`.

## Active Research Topics

- `.claude/research.md` topic `2026-05-16 Camera/Recording/Export V1 Runtime Proof` now includes 2026-05-17 release-readiness updates and should be graduated into `ARCHITECTURE.md`/`DEVELOPMENT.md` after the first published build.
- Current active blockers: 2026-05-19 user-reported camera button hang (`Camera` stuck on loading) blocks SaneVideo `1.0.1` release. Operational warnings remain outside the SaneVideo binary path: pending customer email surfaced by release preflight and Homebrew cask 404.

## Feature Requests / Demand Signals

- No open GitHub issues at the time of this handoff.
- One pending customer email remains surfaced by `release_preflight`; run `/check-inbox` before release cleanup.

- 2026-05-15 launch-readiness audit:
  - SaneVideo remains a hard no-go for public launch.
  - `.outreach.yml` now has an explicit `launch_package` block so launch gates fail on the real blocker: missing creator workflow proof, not missing tracker metadata.
  - First unblocker: run Mini workflow proof for recording/import/edit/export plus the upload-disabled state, then regenerate real customer UI evidence and rerun release preflight.

- 2026-05-12 customer-facing action audit found and fixed pre-live promise drift:
  - README/PRIVACY/ARCHITECTURE no longer claim no network/no telemetry/menu bar integration; YouTube upload is disabled in-app until real OAuth/upload completion exists.
  - Mini `./scripts/SaneMaster.rb verify --timeout 1200` passed 1,682 tests.
  - The stricter SaneProcess customer UI contract now correctly blocks this repo because the existing receipt is source-only and lists JSON as screenshot evidence: missing `required_proof_level`, missing per-action `proof_level`, stale source fingerprint, and unsupported screenshot artifact. Do not treat the customer UI receipt as release proof until real Mini click/visual/TCC evidence is regenerated.

- 2026-05-03 dependency simplification moved SaneVideo to Argmax's current `argmax-oss-swift` package at `1.0.0` for the `WhisperKit` product and removed the unused `swift-grok` dependency. SaneVideo transcription remains WhisperKit-based, while commentary planning stays deterministic via `CommentaryWorkflowPlanner`.
- 2026-04-25 privacy policy update replaced stale `no telemetry/no third-party/no network` claims with the approved privacy-safe analytics standard and current network categories: updates, licensing, aggregate app counts, and optional user-configured export/upload integrations such as YouTube.
- `SaneVideo` now has a standalone workflow-only training lane under `training_data/`.
- Canonical standalone files:
  - `training_data/system_prompt.txt`
  - `training_data/lora_config_mini.yaml`
  - `training_data/challenger_configs/smollm3-3b.yaml`
  - `training_data/eval_commentary_workflow.jsonl`
  - `training_data/eval_workflow_packs.jsonl`
  - `training_data/eval_workflow_guardrails.jsonl`
- `generate_workflow_dataset.py` now stamps the real workflow-only system prompt into `train.jsonl` and `valid.jsonl`.
- Dataset size remains:
  - `train.jsonl`: `115`
  - `valid.jsonl`: `29`

## Latest Verification

- 2026-04-25 corrected standalone challenger run on the Mini now passes the real primary gate:
  - report: `~/SaneApps/outputs/daytrain-sanevideo-commentaryfix-2026-04-25/challenger_report_SaneVideo_smollm3-3b.md`
  - `commentary_workflow`: `4/6 (66%)`
  - `workflow_packs`: `5/5 (100%)`
  - `workflow_guardrails`: `2/4 (50%)`
  - workflow-first: `71%`
  - raw: `73%`
  - operational result: stable `125`-iter run on the Mini in `21 min`, peak mem `3.398 GB`
- Main fixes behind that jump:
  - SaneVideo eval budget raised from the old effective `256` ceiling to `384`, which was necessary to stop clipped multi-item outputs from being mis-scored
  - commentary training prompt now says one-moment commentary requests should return exactly one item, use the brief’s contrast in the concept label, and keep timestamps narrow
  - commentary dataset fixed two real labeling bugs:
    - `old_issues_framing` no longer trains on an overbroad `15:15 -> 35:52` span
    - `repentance_vs_qualification` now trains on the correct `41:19 -> 42:32` window and the actual Peter/David/mercy excerpt
  - compact commentary refs no longer truncate mid-reference
- Local standalone smoke on the Mini completed cleanly with:
  - model: `mlx-community/SmolLM3-3B-4bit`
  - config: `training_data/lora_config_mini.yaml`
  - sweep length: `2` steps
  - peak memory: `3.256 GB`
- Report:
  - `~/SaneApps/outputs/sanevideo-smoke-local/training_report_SaneVideo.md`
- Interpretation:
  - the split workflow-only lane trains cleanly on this Mini
  - the smoke was only for plumbing and memory shape
  - the `0%` workflow score from that run is not meaningful model-quality signal
- 2026-04-25 real standalone Mini runs are now complete:
  - challenger `125`-iter run: `9%` workflow-first under the old capped wrapper report, but `23%` workflow-first on direct uncapped re-eval of the same adapter
  - production `250`-iter run: `47%` workflow-first / `46%` raw in `~/SaneApps/outputs/daytrain-sanevideo-prod-2026-04-25/training_report_SaneVideo.md`
  - primary gate result on production: `commentary_workflow 3/6 (50%)` -> PASS
  - operational result: both runs were stable on the Mini with peak memory under `3.0 GB`

## Automation Root

- `mini-train.sh` now defaults `SaneVideo` to workflow-only eval weighting:
  - `commentary_workflow=4`
  - `workflow_packs=2`
  - `workflow_guardrails=2`
- `mini-train.sh` now gives standalone `SaneVideo` a higher Mini eval token cap so per-case `256` token requests are not clipped to `192`.
- `mini-prepare-automation-root.sh` must hydrate the standalone `SaneVideo` support files into `~/SaneApps-automation`, not just `train.jsonl` and `valid.jsonl`.
- `mini-prepare-automation-root.sh` now also treats `models/sweeps/*` and `models/production_adapter/*` as managed automation overlays so a finished run does not block the next prep.
- Canonical training root for real runs remains `~/SaneApps-automation`.

## Next

1. Fix the four remaining misses from the `71%` challenger:
   - `optics_over_substance`: summary language drift
   - `repentance_vs_qualification`: item mismatch
   - `meeting_voice_brief`: only `2` items
   - `teaching_empty_refs_ok`: item mismatch
2. Cut down the overlong multi-item training examples; `meetingReview` and `salesCoach` repair/guarded variants are still triggering repeated `>1024` token truncation during training.
3. Keep judging readiness only on the strict workflow suites, not the old hybrid gate.
4. Keep `SaneVideo` on the Mini for now; the first blocker is model quality and corpus shape, not Mini stability.

## Launch Ops Calendar - 2026-05-14

- `.outreach.yml` now classifies SaneVideo as `blocked_not_launch_ready`.
- Scheduled gates: runtime workflow proof on 2026-05-26 and creator launch decision on 2026-05-30. Do not run public launch work until the real upload/workflow path has Mini evidence and honest screenshots/video assets.

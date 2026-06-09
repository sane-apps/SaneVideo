# Session Handoff — SaneVideo

**Last updated:** 2026-06-07

## 2026-06-07 Magic Fix Proof / App Store Build 3 Submission

- Tooling/error follow-up, 2026-06-08 10:55 ET: the prior DNS and Xcode errors
  were meaningful. Fixed shared `release.sh` curl live checks to recover from
  a broken macOS resolver using `dig` + `curl --resolve`, added a Node DNS
  fallback hook for Wrangler, and made website deploy fail if Wrangler fails
  instead of printing a false success. SaneVideo website-only deploy then
  succeeded to Cloudflare Pages preview
  `https://2532d9f3.sanevideo-site.pages.dev`; live verification confirmed the
  homepage references only `sanevideo-actual-edit-workflow.png`,
  `sanevideo-magic-fix.png`, and `sanevideo-recording-complete.png`, and
  `/download` has the public `Good first test` copy. Fixed
  `SaneMaster.rb monitor_tests` to use Xcode's correct
  `-only-testing:<identifier>` argument and to print raw log tails when Xcode
  aborts before XCTest output. Remaining local blocker is host Directory
  Services/system resolver state: `whoami`/`id -un` return `501`,
  `getconf DARWIN_USER_CACHE_DIR` returns EIO, `scutil --dns` says no DNS
  configuration, SSH fails before connecting with `No user exists for uid 501`,
  and no-prompt sudo cannot run because the uid is missing from the passwd
  database. This requires host service restart or reboot outside this shell.
- Final capture cleanup, 2026-06-07 23:59 ET: moved the remaining bad baseline
  capture `outputs/visual-audit-20260603/00-recording-mode-baseline.png` to
  Trash because it showed Camera Off, desktop clutter, and a system
  notification. Also moved unused duplicate
  `docs/images/sanevideo-actual-edit-workflow.jpg` to Trash. Current retained
  capture inventory is exactly three App Store PNGs, three public website PNGs,
  two Magic Fix/recording-complete source captures, and the populated editor
  fixture source. Direct capture-contract check passed. Xcode targeted
  regression is currently blocked by local Xcode runner error
  `Code=5 "Input/output error"` before assertions execute. Website redeploy is
  currently blocked by the release wrapper because macOS `getaddrinfo`/curl
  cannot resolve live SaneApps endpoints even though `dig` can resolve them.
- Capture hygiene correction, 2026-06-07 21:45 ET: user rejected the bad mobile
  picture treatment and internal public copy. Removed public/internal wording
  from `docs/download.html`; mobile homepage now shows the copy/CTA first and a
  clean framed app screenshot after it instead of a tiny dark desktop image at
  the top. Bad captures were moved to Trash: camera-off recording screenshot,
  blank-preview timeline screenshot, unsuitable playback media screenshot,
  desktop/system-dialog captures, and unused stock/media source stills. The
  retained capture set is now only:
  `docs/images/sanevideo-actual-edit-workflow.png`,
  `docs/images/sanevideo-magic-fix.png`, and
  `docs/images/sanevideo-recording-complete.png`, generated from actual app
  captures listed in `Screenshots/asset_sources.yml`. App Store screenshot
  generator now produces only `appstore-01-editing-dark-mac.png`,
  `appstore-02-magic-fix-dark-mac.png`, and
  `appstore-03-recording-complete-dark-mac.png`.
- Website polish continuation, 2026-06-07 21:20 ET: researched common
  AI-generic website markers and tightened the homepage to avoid a cheap
  template look. Changes keep navy/teal as the dominant palette, reduce glossy
  generic proof-chip styling, make the real app screenshot more legible, replace
  defensive "real app" copy with workflow-specific language, and keep Magic Fix
  claims tied to visible app UI. Deployed via SaneProcess website-only release
  to Cloudflare Pages preview `https://18b21c72.sanevideo-site.pages.dev`;
  production `https://sanevideo.com/` contains the updated copy and
  `/images/sanevideo-magic-fix.png` returns HTTP 200. Visual proof saved under
  `/Users/stephansmac/SaneApps/outputs/website-polish-20260607/`.
- Continuation verification, 2026-06-07 20:30 ET: visually inspected
  `docs/images/sanevideo-magic-fix.png` and
  `Screenshots/appstore-03-magic-fix-dark-mac.png`. Both show a loaded editor
  preview, selected real timeline clip, Magic Fix progress modal at 40%, and
  `100% On-Device`; the preview is not blank. Live `https://sanevideo.com/`
  references `/images/sanevideo-magic-fix.png`, labels it as Magic Fix actively
  analyzing a selected clip, and the image returns HTTP 200. Targeted Mini
  regressions passed for
  `MagicFixTests/testAudioEnhancementIsSkippedForVideoOnlyClips` and
  `ReleaseReadinessRegressionTests/testAppStoreScreenshotStoryboardAndGeneratorCoverLaunchSellingPoints`.
  `./scripts/SaneMaster.rb customer_ui_contract --json --no-exit` is green
  with 19 actions. `./scripts/SaneMaster.rb appstore_preflight` passed with one
  warning only: 62 uncommitted files. ASC state remains macOS `1.0.1`
  `WAITING_FOR_REVIEW`, and IAP `com.sanevideo.app.pro.access.v2` remains
  `WAITING_FOR_REVIEW`.
- User correctly flagged that the prior Magic Fix App Store screenshot did not
  prove Magic Fix was working; it showed the inspector row but the preview was
  effectively blank. Re-captured the real app with a container-local fixture and
  Magic Fix actively running. Clean proof source:
  `outputs/magic-fix-runtime-proof/06-magic-fix-window-patched.png`.
- Current App Store screenshot `Screenshots/appstore-03-magic-fix-dark-mac.png`
  was visually inspected after regeneration. It shows the loaded editor preview,
  selected real timeline clip, inspector Magic Fix row, `100% On-Device`, and a
  Magic Fix progress modal analyzing cuts at 40%. This is real runtime UI, not a
  generated/mock screenshot, and the preview is not blank.
- Product fix made during proof capture: Magic Fix now skips audio enhancement
  for video-only clips instead of surfacing an audio-enhancement failure when
  the clip has no audio track. Touched:
  `SaneVideo/Services/SmartFeatures/MagicFixService.swift`,
  `SaneVideo/State/ProjectState+SmartFeatures.swift`, and
  `SaneVideoTests/Features/AI/MagicFixTests.swift`.
- Verification passed:
  - Focused Magic Fix regression:
    `MagicFixTests/testAudioEnhancementIsSkippedForVideoOnlyClips`.
  - Screenshot/storyboard regression:
    `ReleaseReadinessRegressionTests/testAppStoreScreenshotStoryboardAndGeneratorCoverLaunchSellingPoints`.
  - Full App Store preflight: 701 tests passed; preflight completed with only
    the expected dirty-worktree warning.
- Website was redeployed with the corrected Magic Fix material and explicit
  labels/descriptions that say Magic Fix is running/actively analyzing, not just
  visible. Production checks verified `https://sanevideo.com/` references
  `/images/sanevideo-magic-fix.png`, includes the updated Magic Fix running
  copy, and the live image returns HTTP 200.
- App Store correction supersedes the earlier build 2 submission. Build number
  was bumped to `3`, App Store build `3` processed successfully in ASC, the
  corrected screenshot set was uploaded, IAP
  `com.sanevideo.app.pro.access.v2` remains `WAITING_FOR_REVIEW` with USA price
  `$3.49`, and macOS version `1.0.1` is now `WAITING_FOR_REVIEW` with build `3`
  attached. ASC build id:
  `b3008219-ec9b-495e-83c5-3c7ba82da6e6`.

## 2026-06-07 Website / Marketing Assets Live Correction

- SaneVideo public site is live again at `https://sanevideo.com/` after replacing
  the paused proof-rebuild homepage with a real-product page. Production
  verification: `https://sanevideo.com/` and `https://sanevideo.com/download`
  both return HTTP 200; the release wrapper verified the live appcast at
  `https://sanevideo.com/appcast.xml`. The 2026-06-07 Magic Fix redeploy also
  verified `https://sanevideo.com/images/sanevideo-magic-fix.png` returns HTTP
  200 as a 1512x1012 PNG.
- Current public screenshots are real SaneVideo app states only:
  `sanevideo-recording.png`, `sanevideo-actual-edit-workflow.png`,
  `sanevideo-magic-fix.png`, and `sanevideo-recording-complete.png`. The Magic
  Fix image is generated from the real app capture
  `outputs/appstore-real-captures/04-inspector-magic-fix.png`; it visibly shows
  the inspector Magic Fix row, a selected timeline clip, and 100% On-Device
  status. Removed stale export/captions screenshots from the public proof set
  because those states did not have strong enough matching real captures for
  current marketing claims.
- App Store screenshot generator now outputs four App Store screenshots from
  real app captures only:
  `appstore-01-recording-dark-mac.png`,
  `appstore-02-editing-dark-mac.png`,
  `appstore-03-magic-fix-dark-mac.png`, and
  `appstore-04-recording-complete-dark-mac.png`. The storyboard/generator/test
  forbid fake UI, duplicate source captures, synthetic drawing, and stale
  export/caption claims without matching real screenshots.
- App Store Connect correction: Apple locked screenshots while `1.0.1` was
  `WAITING_FOR_REVIEW`, so the version was withdrawn via `appstore_submit.rb
  --withdraw-version 1.0.1`, moving it to `DEVELOPER_REJECTED`. The earlier
  build 2 correction was superseded by the 2026-06-07 build 3 submission above;
  ASC version-state preflight now confirms SaneVideo macOS `1.0.1` is
  `WAITING_FOR_REVIEW` with build 3 attached.
- Verification: focused Xcode regression
  `ReleaseReadinessRegressionTests/testAppStoreScreenshotStoryboardAndGeneratorCoverLaunchSellingPoints`
  passed after the site/test updates. Live source checks confirm expected copy
  and real screenshot references are present, while `Proof rebuild in progress`,
  `mockups`, `synthetic product screenshots`, and stale screenshot names are
  absent. The Magic Fix asset was visually inspected locally after generation
  and fetched from production as `/tmp/sanevideo-live-magic-fix.png`.

## 2026-06-05 App Store Rejection / IAP Rotation

- App Store Connect now reports SaneVideo macOS `1.0.1` as
  `WAITING_FOR_REVIEW` with review submission
  `3fb2df03-cc39-4e68-a1ce-bc7ed030f2f2`. The prior rejected submission
  `0599add7-ee35-4937-9b44-8671ea59a04c` is superseded.
- The old non-consumable IAP `com.sanevideo.app.pro.unlock` was in
  `DEVELOPER_ACTION_NEEDED` after rejection. It was deleted from App Store
  Connect, and the app was rotated to `com.sanevideo.app.pro.access.v2`.
- Updated App Store metadata/config references in `.saneprocess`,
  `project.yml`, `SaneVideo/Info-AppStore.plist`,
  `SaneVideo.xcodeproj/project.pbxproj`, and
  `SaneVideoTests/Regression/ReleaseReadinessRegressionTests.swift`.
- New IAP `com.sanevideo.app.pro.access.v2` was created in App Store Connect
  with USA price `$3.49`, localization, screenshot, and availability; a fresh
  Included Assets receipt verifies it is attached for macOS `1.0.1`.
- SaneVideo App Store screenshots were replaced with real app UI screenshots
  generated from the Mini runtime proof capture, not synthetic UI. The screenshot
  storyboard/generator/regression test now forbid fake UI/color bars/composites
  and require real app evidence. App Review reply was sent explaining the new
  screenshots and Movies-folder entitlement use.
- ASC Game Center was disabled for macOS `1.0.1` after the submit helper found
  the version linked Game Center while the build lacked the entitlement.
  SaneProcess preflight now checks this on both iOS and macOS. App Store
  preflight passed with warnings only, and review-submission recovery submitted
  the version after Apple returned transient reviewSubmissions/API states.
  Release-pending sweep found no `PENDING_DEVELOPER_RELEASE` versions.

## 2026-06-03 Website Proof Reset / Mini Access Restored

- User rejected the current SaneVideo website screenshots because they show fake/generated UI instead of the actual app. The local homepage remains paused/noindex until every public product screenshot is screenshot-level accurate.
- 2026-06-04 update: `docs/images/sanevideo-actual-edit-workflow.*`, `docs/images/sanevideo-recording.*`, `docs/images/sanevideo-captions-demo-pack.*`, `docs/images/sanevideo-export.*`, and `docs/images/sanevideo-magic-fix.*` were overwritten with real captured app screenshots from `outputs/mini-runtime-proof/` and `outputs/website-real-proof/`. The PNG hashes match the source proof captures. Do not treat the filename labels as feature-proof unless the visible UI state proves that specific feature; the full marketing page should stay paused until feature-specific captures exist for Transcript, Export, Thumbnail, Voiceover, Shorts, and the end-to-end workflow video.
- 2026-06-04 runtime-proof continuation: editor bootstrap now works through LaunchServices with real fixture arguments. Code changes:
  - `TestEnvironment.shouldOpenEditor` recognizes `SANEVIDEO_OPEN_EDITOR=1`, explicit `-test_asset_path` / `--test-asset-path=...`, and `--automation-transcript-path`.
  - `ProjectStore` and `ProjectState` use `TestEnvironment.shouldOpenEditor` instead of stale raw `OPEN_EDITOR` checks.
  - Main scene changed from `Window(...)` to `WindowGroup(...)` so the primary app window is created at launch.
  - Focused Mini test passed: `./scripts/SaneMaster.rb monitor_tests SaneVideo SaneVideoTests/ProjectEditingTests/testAutomationEnvironmentFlagsResolveExistingPaths 600`.
  - Clean Mini app-window proof: `outputs/visual-audit-20260603/01-editor-real-fixture.png` with receipt `outputs/visual-audit-20260603/receipt.json`. Logs showed `website-demo-video-call.mp4` imported, 5 transcript captions applied, a timeline clip selected, and the main window restored.
  - Superseded 2026-06-07: the screenshot/storyboard release gate now passes
    with the live real-product page and four real App Store screenshots,
    including a dedicated Magic Fix inspector capture.
  - Remaining runtime/marketing proof gap: coordinate clicks through Mini `cliclick` did not reliably switch left-rail states for Transcript, Thumbnail, Voiceover, or Shorts. Capture these manually or add reliable app-supported automation before unpausing the full marketing page.
- Source homepage `docs/index.html` was reset to a `noindex, follow` proof-rebuild page so the repo does not present synthetic proof as a launchable product page. Do not deploy a full marketing page until real Mini screenshots/video exist.
- Download page `docs/download.html` now says the full marketing page is paused while the proof set is rebuilt, and keeps the public testing download/support links available.
- 2026-06-04 website smoke proof: local Playwright run through the bundled runtime saved `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-real-proof/sanevideo-paused-site-desktop-20260604.png` and `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-real-proof/sanevideo-paused-site-mobile-20260604.png`; both load only `images/icon.png`, have no failed requests, and keep `robots=noindex, follow`.
- Mini access is restored for this remote Codex session. `ssh mini` now routes through Cloudflare Access using `mini-ssh-host.saneapps.com` TXT plus `cloudflared access ssh`, while `mini-lan` preserves the same-Wi-Fi `.local` route. `ssh mini 'hostname; whoami; pwd'` succeeds and the canonical screenshot wrapper works through the `mini` alias again.
- The Mini-side bridge is a launchd-managed quick tunnel: `com.saneapps.mini-remote-ssh-tunnel` runs `~/SaneApps/infra/scripts/mini-remote-ssh-tunnel.sh`, publishes the current `*.trycloudflare.com` host to DNS TXT, and logs to `~/Library/Logs/SaneApps/mini-remote-ssh-tunnel.log`. Reproducible setup is documented in `~/SaneApps/infra/SaneProcess/AGENTS.md`, `DEVELOPMENT.md`, and `scripts/mini/README.md`; scripts added under `SaneProcess/scripts/mini/`.
- Mini desktop is visually clean after clearing the macOS background-item notification for the tunnel LaunchAgent. Current clean desktop proof: `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-real-proof/codex-shot-2026-06-03_17-50-56.png`.
- Next Mini-attached run should capture the actual app with a real stock video, not web composites:
  1. Use the existing fixture `Tests/Assets/website-demo-video-call.mp4` and paired transcript `Tests/Assets/website-demo-captions.srt`.
  2. Clear quarantine/provenance xattrs on the Mini/container copy before import, as noted in the May 27 handoff.
  3. Launch SaneVideo on the Mini with editor bootstrap and automation transcript env: `OPEN_EDITOR=1 TEST_ASSET_NAME=website-demo-video-call.mp4 AUTOMATION_TRANSCRIPT_PATH=$PWD/Tests/Assets/website-demo-captions.srt SANEAPPS_DISABLE_KEYCHAIN=1 SANEAPPS_PERMISSIONLESS_AUTOMATION=1 ./scripts/SaneMaster.rb test_mode`.
  4. Before every capture, use the canonical Mini screenshot wrapper and inspect the desktop for blockers: `~/SaneApps/infra/SaneProcess/scripts/mini/capture-mini-screenshot.sh desktop --copy-to outputs/website-real-proof`.
  5. Required real-app states: loaded editor/timeline, captions/transcript, export sheet or completed export, thumbnail picker, voiceover sheet, shorts/repurposing sheet, and one end-to-end workflow video if the app remains stable.
  6. If clicking any customer-facing control terminates SaneVideo cleanly again, capture the full Mini desktop immediately, collect recent logs/crashes, and fix that runtime blocker before attempting marketing assets.

## Current State

- 2026-05-27 website/screenshot remediation is still in progress; do not republish the full site yet:
  - Live `https://sanevideo.com/` was intentionally replaced with an under-construction page until user approval. The public page is `noindex, follow` and says the screenshots/video proof are being rebuilt from the real app.
  - Confirmed official icon remains the dark blue/cyan double-chevron. Do not use the old clapperboard icon.
  - Mini signed Release launch path is verified: `/Applications/SaneVideo.app` is signed by `Developer ID Application: Stephan Joseph (M78L6FXD48)`.
  - Runtime UI fixes made during this pass:
    - `PlaybackState.isPreparingComposition` now prevents the preview from showing a perpetual loading chip when it is only using the thumbnail fallback.
    - Magic Fix/Core Cleanup rows and action buttons have higher contrast, brighter labels, clearer icon chips, and tighter text fitting.
    - Shared SaneMaster `test_mode` now passes `AUTOMATION_TRANSCRIPT_PATH` and related automation env vars through LaunchServices.
    - Mini `mini-codex-keepalive.sh` no longer opens Codex while a SaneApps app is running; the current Mini keepalive agent was booted out after repeated Codex keychain prompts contaminated captures.
    - Follow-up keychain root cause/fix: the visible Mini keychain dialogs came from two tool paths, not from SaneVideo app code. The old `iCloudNotificationAgent` dialog lined up with signed Release `test_mode`/release signing prep that globally mutated/unlocked the login keychain. SaneProcess now gates those login-keychain mutations behind explicit env flags and stamps repeated partition-list grants. A later `Codex wants to use the "login" keychain` dialog was from the Mini Codex app-server/remote-control layer. The Mini Codex keepalive is now opt-in only, the LaunchAgent label is disabled, and Mini `~/.codex/app-server-daemon/settings.json` has `remoteControlEnabled: false`; kill orphan `codex app-server` processes before leaving the Mini idle.
  - Clean proof paths captured so far:
    - Loaded real video/timeline without loading overlay: `/Users/sj/SaneApps/apps/SaneVideo/outputs/mini-runtime-proof/sanevideo-baseline-real-video-005703.png`
    - Magic Fix contrast/spacing pass: `/Users/sj/SaneApps/apps/SaneVideo/outputs/mini-runtime-proof/sanevideo-magic-fix-ui-final-184902.png`
    - Runtime blocker evidence for Mini Codex keychain prompt: `/Users/sj/SaneApps/apps/SaneVideo/outputs/mini-runtime-proof/sanevideo-runtime-blocker-020328.png`
  - Current blocker: after the Codex keychain prompt was cleared and stale SaneBar/Safari/TextEdit surfaces were removed, SaneVideo loaded the real clip and captions. However, clicking customer-facing controls during the direct `open --fresh --env ...` run repeatedly caused SaneVideo to terminate cleanly with no crash report. This prevented clean screenshot-level capture of Transcript/Export/Thumbnail/Voiceover/Shorts. Do not claim the website proof set is complete until this interaction/runtime blocker is fixed and each feature state has a clean Mini screenshot.
  - Sample asset note: the downloaded Mixkit clip is staged in the app container at `~/Library/Containers/com.sanevideo.app/Data/Tests/Assets/test_video.mp4`. Its quarantine/provenance xattrs must be cleared before import; otherwise SaneVideo shows `Import failed: ... don't have permission to view it`. After clearing xattrs and using a container-local SRT path, the saved `.svproj` had one clip and 5 captions.
  - Competitor benchmark research was added to `.claude/research.md` on 2026-05-27: Screen Studio/Cap/Descript/CapCut/VEED/Loom all use real UI or real workflow product proof, clear feature-specific states, and human copy. Avoid faux rendered blocks and vague AI claims.

- 2026-05-26 SaneVideo website visual remediation is live:
  - Replaced weak synthetic/empty website proof with a real-media proof set: hero loop, loaded sample project, recording, Magic Fix, captions/demo-pack, and export cards. Source media provenance is tracked in `Screenshots/asset_sources.yml`.
  - Rebuilt the website icon, Xcode app icon set, and `Resources/DMGIcon.icns` from the official dark blue/cyan double-chevron source at `SaneVideo.png`. No clapperboard references were found in the audited website files.
  - Website-only deploy completed through `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project /Users/sj/SaneApps/apps/SaneVideo --website-only`; final Cloudflare Pages deployment: `https://593bd017.sanevideo-site.pages.dev`.
  - Live curl verification passed for `https://sanevideo.com/`, hero video, icon, all five screenshot JPGs, sitemap, robots, appcast, and redirects from removed internal docs to `/`.
  - Live Playwright visual proof saved:
    - `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-assets/sanevideo-live-desktop-proof.png`
    - `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-assets/sanevideo-live-mobile-proof.png`
  - Verification intentionally did not run full SaneVideo `verify`; the 2026-05-25 Mini watchdog panic was tied to export-heavy integration tests and this was a website/icon/screenshot change. Used static asset checks, Swift parse checks, screenshot generator run, browser visual proof, and live URL verification instead.
  - Remaining account-level issue: `https://www.sanevideo.com/` still returns `200` instead of redirecting to apex; fix requires Cloudflare zone-level redirect, not Pages `_redirects`.

- 2026-05-25 22:21 EDT conversion/copy correction verified:
  - Public-testing monetization copy now says public testing is free and early
    Pro support is optional at `$3.49` through `2026-07-25`.
  - Homepage/download CTAs now say `Support early Pro for $3.49` instead of
    implying Pro is required to use the public testing build.
  - `ReleaseReadinessRegressionTests` was updated to assert the current
    optional-public-testing Pro language, and the pricing regression still
    blocks old `$29/$49` launch-special copy.
  - Verification: Mini `./scripts/SaneMaster.rb verify --timeout 1800` passed
    `1210` tests in `290s` after the copy/test alignment patch.
  - Business signal: 30-day analytics show `609` downloads, `45` checkout
    clicks, and `0` license activations, so the current public-testing offer has
    not converted yet.

- 2026-05-25 SaneVideo website emergency copy/proof audit and live deploy:
  - User rejected the site voice and screenshot proof. Three subagents audited the live/local site and agreed the page needs real proof assets: loaded timeline project, active recording, Magic Fix cleanup, captions/demo-pack, and completed export. Current screenshots remain weak because they do not show enough sample media or smart features in a credible working state.
  - Homepage and download copy were rewritten live to use screen-recorder/editor category language: record screen/camera/mic, cut dead air, add captions, export local files, Magic Fix, auto-zoom/cursor-aware effects, MP4/GIF/thumbnails/demo packs, and no cloud detour. Removed confusing “surfaces/workflow/support Pro” sales copy.
  - Public internal docs were removed from the deploy surface: `docs/audit_report_2026-01-01.md` and `docs/session_notes_2026-01-08.md` were deleted; `docs/appstore_screenshot_storyboard.yml` moved to `Screenshots/appstore_screenshot_storyboard.yml`; `ReleaseReadinessRegressionTests` now points to the new location.
  - Added website hygiene files: `docs/sitemap.xml`, `docs/robots.txt`, `docs/_headers`, and `docs/_redirects`. Live checks verified sitemap XML, robots, and 301 redirects from the old internal doc URLs to `/`.
  - Website-only deploy completed through `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project /Users/sj/SaneApps/apps/SaneVideo --website-only`; final Cloudflare Pages deployment: `https://7cc6dff5.sanevideo-site.pages.dev`.
  - Live verification passed for `https://sanevideo.com/` new homepage copy, `https://sanevideo.com/download` new download copy, `https://sanevideo.com/sitemap.xml`, and internal-doc redirects. Local Playwright screenshots saved:
    - `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-copy/sanevideo-home-copy-desktop.png`
    - `/Users/sj/SaneApps/apps/SaneVideo/outputs/website-copy/sanevideo-home-copy-mobile.png`
  - Remaining account-level issue: `https://www.sanevideo.com/` still returns `200` instead of redirecting to apex. Cloudflare documentation says this requires a zone-level Bulk Redirect or Redirect Rule; Pages `_redirects` cannot fix the duplicate host.

- 2026-05-25 SaneVideo 1.0.1 public testing release is live/submitted:
  - Direct download channel is live and verified:
    - ZIP: `https://dist.sanevideo.com/updates/SaneVideo-1.0.1.zip` returned HTTP 200 with `content-length: 8447038`.
    - Appcast: `https://sanevideo.com/appcast.xml` contains exactly the `1.0.1` entry and `SaneVideo-1.0.1.zip`.
    - Website/download copy advertises public testing and Pro 50% off at `$3.49` through `2026-07-25`.
    - Email webhook live config was updated and verified for `SaneVideo-1.0.1.zip`.
  - Mac App Store submission is complete:
    - ASC macOS version `1.0.1` is `WAITING_FOR_REVIEW`.
    - Review submission id `0599add7-ee35-4937-9b44-8671ea59a04c` is `WAITING_FOR_REVIEW`.
    - Uploaded build `2` is `VALID`, id `d8e8ba90-6248-4995-aef0-a0f0bcec4f34`, uploaded `2026-05-25T14:49:30-07:00`.
    - IAP `com.sanevideo.app.pro.unlock` is `WAITING_FOR_REVIEW` and USA price schedule verified at `$3.49`.
  - App Store preflight passed before submission with warnings only for transient uncommitted receipt state; after commit `16bcb25`, the App Store submit wrapper rechecked the strict customer UI contract and submitted successfully.
  - Final release commits on SaneVideo `main`:
    - `75dbef8 Prepare SaneVideo 1.0.1 public testing release`
    - `374c5e1 Use build settings for SaneVideo bundle versions`
    - `572afb3 chore: sync 1.0.1 version metadata and site download links`
    - `8ff29a5 chore: sync release metadata for v1.0.1`
    - `16bcb25 Update App Review notes and UI receipt`
    - `dda4c33 Redesign SaneVideo website for public testing`
  - The live website was replaced after user review rejected the placeholder page. New page uses actual SaneVideo screenshots from `Screenshots/appstore-*-dark-mac.png`, SaneApps-style navigation/CTAs, workflow/product sections, Basic/Pro public-testing pricing, and privacy/local-first proof.
  - Website deployment receipt:
    - `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project /Users/sj/SaneApps/apps/SaneVideo --website-only`
    - Cloudflare Pages deployment: `https://45e7db06.sanevideo-site.pages.dev`
    - Live curl verification found new H1, `images/sanevideo-recording.png`, `$3.49`, `July 25, 2026`, and `PolyForm Shield` on `https://sanevideo.com/`.
    - Playwright visual checks on live/local desktop and mobile showed no broken images and no horizontal overflow. Saved local visual proof paths:
      - `/Users/sj/SaneApps/apps/SaneVideo/.playwright-cli/page-2026-05-25T21-48-36-925Z.png` (local desktop, later trashed with generated Playwright artifacts)
      - `/Users/sj/SaneApps/apps/SaneVideo/.playwright-cli/page-2026-05-25T21-48-49-960Z.png` (local mobile, later trashed with generated Playwright artifacts)
      - `/Users/sj/SaneApps/apps/SaneVideo/.playwright-cli/page-2026-05-25T21-51-23-533Z.png` (live desktop, later trashed with generated Playwright artifacts)
  - Mini verification after website commit `dda4c33` passed through pre-push: `./scripts/SaneMaster.rb verify` passed `1208 tests` in `389s`. Warnings remain existing SwiftLint/style/file-length warnings and `Settings container not using shared SaneUI shell: SaneVideo`.
  - Runtime blocker/tooling lesson from this release: the Mini visual guard caught dirty workspace state after the user reported a visible update prompt/dialog. Treat Finder/frontmost non-target windows, helper apps, notifications, and failed prompt scans as invalid evidence. Do not count GUI verification from logs alone when any runtime command stalls or the user says a dialog is visible.
  - Sparkle update prompt fix is included in 1.0.1: direct `Info.plist` sets `SUEnableAutomaticChecks=false`; App Store plist remains Sparkle-free. Clean proof screenshot from the fixed app: `/Users/sj/Desktop/Screenshots/SaneVideo/update-prompt-fixed-app-20260525-151343.png`.

- 2026-05-25 SaneVideo 1.0.1 publish pass:
  - Rule 0 classification: release-readiness/runtime blocker. Do not publish direct download, website, App Store/TestFlight, or public launch copy from this state.
  - Timeline review found and fixed a real trim bug: right-edge trim handles were sending `duration - trimEnd` even though `ProjectState.updateClipTrim` expects absolute `trimEnd`. `ClipTrimHandle` now resolves absolute trim positions and `TrimHandleTests.testRightTrimHandleReturnsAbsoluteTrimEnd` guards the regression.
  - User reported a roughly 10 second black-screen gap after manually clicking Allow Video. Root-cause evidence in logs showed `AVCaptureVideoPreviewLayer` being added after `AVCaptureSession.startRunning`, triggering AVFoundation graph teardown/restart (`addVideoPreviewLayer` / `_stopAndTearDownGraph`). The current candidate replaces the preview-layer path with a sample-buffer renderer and publishes the session before capture start.
  - Camera runtime proof on the Mini after the patch:
    - Baseline off state: `/Users/sj/Desktop/Screenshots/SaneVideo-review/18-baseline-sample-buffer.png`
    - Post-click full visual-smoke proof: `/Users/sj/Desktop/Screenshots/SaneVideo-review/19-after-sample-buffer-preview.png`
    - Second post-click app-only proof: `/Users/sj/Desktop/Screenshots/SaneVideo-review/20-after-click-app-only.png`
    - Logs after the sample-buffer preview no longer show `addVideoPreviewLayer` or `_stopAndTearDownGraph`.
  - Mini verification passed after the camera/timeline patches: latest `./scripts/SaneMaster.rb verify --no-grant-permissions --timeout 1200` passed `1207 tests` in `298s`.
  - `./scripts/SaneMaster.rb release_preflight` is red, so publish is blocked. Primary blocker: stale Customer UI action contract and missing May 16 screenshot/workflow artifacts. Warnings: dirty worktree, UserDefaults/migration code changed so upgrade-path testing is required, appcast still at 1.0 while project is 1.0.1, 5 pending customer emails, Homebrew tap cask 404.
  - `SANEMASTER_GRANT_PERMISSIONS=0 ./scripts/SaneMaster.rb appstore_preflight` is red. Additional App Store blockers: missing `Screenshots/appstore-*-dark-mac.png`, active ASC macOS 1.0 lane is still `WAITING_FOR_REVIEW` while local target is 1.0.1, and the strict visual contract is stale. `.saneprocess` metadata declarations for copyright/content rights/export compliance were added locally and synced to the Mini after this failure.
  - `./scripts/SaneMaster.rb launch_readiness --json --max-age-days 7` is red: no public launch until real creator workflow proof exists, `.outreach.yml` has proof assets, customer UI receipt is valid runtime/visual proof, and release preflight is green.
  - Pricing/copy note: user wants public testing positioning with 50% off through 2026-07-25. Do not advertise this live until the actual App Store/IAP or direct-purchase price schedule is set; current preflight did not clear publish.

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
- No active SaneVideo 1.0.1 publish blocker remains after the 2026-05-25 release. Operational warnings remain outside the SaneVideo binary path: pending customer email surfaced by release preflight, Homebrew tap cask 404 / not allowlisted, existing SwiftLint style/file-length warnings, and `Settings container not using shared SaneUI shell: SaneVideo`.

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
# 2026-05-25 Mini Watchdog Panic During Full Verify

- While working on website screenshots and the app icon, I incorrectly ran full `./scripts/SaneMaster.rb verify` for a website/icon-only change.
- The Mini stopped responding during SaneVideo export-heavy integration tests and rebooted.
- Crash report: `/Library/Logs/DiagnosticReports/panic-full-2026-05-25-233949.0002.panic` on the Mini.
- Panic summary: `watchdog timeout: no checkins from watchdogd in 93 seconds`; panicked task was `kernel_task`, with `AppleARMWatchdogTimer` / `AppleInterruptController` in the backtrace.
- Local test log immediately before the reboot was in SaneVideo export tests, around `ExportEdgeCaseIntegrationTests`, with repeated 4K AVAssetWriter exports and custom compositor work.
- This is the second Mini watchdog reset on 2026-05-25; earlier reset evidence exists in `/Library/Logs/DiagnosticReports/ResetCounter-2026-05-25-181832.diag` and the local infra incident folder `/Users/sj/SaneApps/infra/SaneProcess/outputs/mini-incident-20260525-1817`.
- Rule going forward: do **not** run full SaneVideo `SaneMaster verify` on the 8GB Mini for website-only, screenshot-only, docs-only, or icon-only changes. Use static checks, screenshot generator verification, browser visual proof, and website deploy verification. If app build proof is genuinely needed for an icon-only change, use a narrow build/test path after the Mini is cool and with explicit user approval; avoid the export integration suite unless the change touches export/audio/compositor behavior.
- Cleanup done after reboot: terminated the leftover Mini `SaneVideo.app` process from the interrupted test run; no `xcodebuild`, `xctest`, `swift-frontend`, or SaneVideo test process remained.

# 2026-06-07 App Store Screenshot Asset Repair

- Replaced synthetic App Store screenshot generation with real-app-capture generation in `scripts/generate_appstore_screenshots.swift`.
- Current generated App Store set uses only real SaneVideo screenshots:
  - `Screenshots/appstore-01-recording-dark-mac.png`
  - `Screenshots/appstore-02-editing-dark-mac.png`
  - `Screenshots/appstore-03-magic-fix-dark-mac.png`
  - `Screenshots/appstore-04-recording-complete-dark-mac.png`
- The generator now rejects duplicate source captures and removes stale generated export/captions/inspector website images when no matching real capture exists.
- Storyboard policy moved from aspirational export/captions claims to verified states: recording controls, timeline editor, Magic Fix inspector, and recording-complete actions.
- Verification:
  - `swift scripts/generate_appstore_screenshots.swift` passed and generated 5760x3600 App Store PNGs plus 1512x1012 website PNGs.
  - Focused regression passed: `xcodebuild -project SaneVideo.xcodeproj -scheme SaneVideo -destination 'platform=macOS' -only-testing:SaneVideoTests/ReleaseReadinessRegressionTests/testAppStoreScreenshotStoryboardAndGeneratorCoverLaunchSellingPoints test`.
  - Full local wrapper verify passed: `./scripts/SaneMaster.rb verify --timeout 600` with 1210 tests in 294s.
- Remaining launch polish: capture stronger real screenshots for export/captions/Magic Fix before making those claims in App Store Connect or the public website.

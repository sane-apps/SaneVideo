# Session Handoff — SaneVideo

**Last updated:** 2026-06-16

## 2026-06-16 Pricing and Website Receipt

- User set SaneVideo target price to `$14.99` once and reported Lemon Squeezy
  pricing was updated.
- Direct app config, App Store IAP config, public download page, and outreach
  pricing proof now use `$14.99` with no `SANEVIDEO50`, `$3.49`, `$6.99`, or
  July 25 discount copy in current public pricing surfaces.
- Lemon Squeezy API confirmed the default SaneVideo variant price is now `1499`
  cents; `https://go.saneapps.com/buy/sanevideo` redirects through Lemon
  checkout to HTTP 200.
- App Store Connect IAP helper observed USA `$3.49`, created the USA `$14.99`
  price schedule, and left the IAP in `APPROVED` state.
- Mini `SaneMaster verify --timeout 1200` passed `1211` tests in `307s`.
- `sanevideo.com` was deployed from the Mini via website-only release; social
  card and SEO audits passed for 4 pages, and live `/download` plus appcast
  checks passed.
- Live page check confirmed `https://sanevideo.com/download` contains `$14.99`
  and no stale `$3.49`, `$6.99`, `SANEVIDEO50`, or `July 25` copy.

## 2026-06-14 Pricing, Checkout, and SaneApps Listing

- SaneVideo Pro public price is now `$14.99` one-time purchase across app
  pricing config, regression tests, and the public download page.
- Lemon Squeezy public API only allows `GET/HEAD` for variant `1703963`, so the
  dashboard variant still reports its old base price via API. A live non-test
  Lemon Squeezy custom checkout was created instead with `custom_price: 1499`,
  `variant_id: 1703963`, no expiration, and id
  `dc3fd28c-8e5c-4a97-8825-9a8d8d02d0d7`.
- `https://go.saneapps.com/buy/sanevideo` now redirects to that $14.99 custom
  checkout and no longer appends stale automatic discount codes.
- SaneVideo variant `1703963` now also backs the live SaneApps Everything
  Bundle custom checkout because its license limit is unlimited. Bundle checkout
  id: `b2566137-793d-4d72-8860-3f85cdf44bbb`; price: `$49.99`; route:
  `https://go.saneapps.com/buy/bundle`. Scope is current direct Mac apps only:
  SaneBar, SaneClip, SaneClick, SaneHosts, SaneSales for Mac, and SaneVideo.
  App Store purchases, SaneScan, and App Store builds remain Apple-managed and
  are not unlocked by the Lemon license key.
- SaneVideo site adds the bundle as a secondary, non-interruptive upsell near
  the public testing download/Pro purchase surfaces. No modal or popup was
  added. Visual receipts:
  `/Users/sj/SaneApps/outputs/visual-audit-20260614-bundle/`.
- Bundle copy was refined after user feedback to keep public pages as sales
  copy only: "all current direct Mac Pro apps in one purchase." Avoid
  fulfillment instructions, key-pasting steps, and defensive App Store
  exclusion language on marketing surfaces; purchase instructions belong in the
  post-purchase email/receipt.
- Central SaneApps site was updated so live projects are listed correctly:
  SaneBar, SaneClip, SaneHosts, SaneClick, SaneSales, SaneScan, and SaneVideo
  are shown as live; SaneSync is not shown as live.
- SaneApps and SaneVideo sites were deployed from the Mini:
  `https://882c896f.saneapps-site.pages.dev` and
  `https://afa7ba5d.sanevideo-site.pages.dev`.
- Verification receipts:
  - Mini SaneVideo `./scripts/SaneMaster.rb verify --timeout 600` passed
    `1212` tests in `291s`.
  - SaneProcess checkout/link validation tests passed `60/60` locally and on
    the Mini.
  - Live HTTP checks confirmed `saneapps.com` includes SaneVideo/SaneSales/
    SaneScan, omits SaneSync as live, and contains no stale `$6.99` copy.
  - Live HTTP checks confirmed `sanevideo.com/download` contains `$14.99`, no
    old `$3.49`, and the buy route redirects to the custom checkout without a
    `checkout[discount_code]` parameter.
  - Visual receipts are in
    `/Users/sj/SaneApps/outputs/visual-audit-20260614-saneapps-sanevideo/`.

## 2026-06-14 Website Workflow Overflow Fix

- User reported the live SaneVideo website looked horrible in Safari. The
  visible failure was the Workflow section: three huge screenshot cards filled
  the viewport and pushed the page sideways/vertically.
- Root cause: `docs/index.html` gave the workflow screenshots `width="1512"`
  and `height="1012"` attributes but had no `.workflow img` CSS constraint, so
  the browser rendered each image at natural width inside a three-column grid.
- Fix: added `.workflow img { display: block; width: 100%; height: auto; }` so
  the images scale to their cards instead of breaking the grid.
- Local Browser verification:
  - Desktop viewport `1952x1094`: no horizontal overflow; workflow cards are
    about `381x311`, images about `379x254`.
  - Mobile viewport `390x844`: no horizontal overflow; workflow cards stay
    within the viewport.
  - Screenshot receipts:
    `/Users/sj/Desktop/Screenshots/sanevideo-website-workflow-fixed-desktop-20260614.png`
    and
    `/Users/sj/Desktop/Screenshots/sanevideo-website-workflow-fixed-mobile-20260614.png`.
- This fixes the obvious live layout bug. It does not resolve the deeper
  governance drift below: prior handoff says the full homepage should stay
  paused/noindex until all real proof assets exist, but current live/source
  homepage is a full indexed marketing page.

## 2026-06-14 Website Proof Asset Refresh

- User rejected the public proof images because the video-complete/recording
  proof had a blank preview and the workflow used the same woman-at-laptop
  stock clip repeatedly.
- Replaced the public workflow proof set with three varied real SaneVideo app
  captures made on the Mini from local stock clips:
  - `docs/images/sanevideo-meeting-workflow.jpg` from
    `outputs/appstore-real-captures/01-editor-meeting.png` and
    `outputs/stock-source/mixkit-business-people-meeting-4809.mp4`.
  - `docs/images/sanevideo-captions-transcribing.jpg` from
    `outputs/appstore-real-captures/04-inspector-magic-fix-varied.png` and
    `outputs/stock-source/mixkit-man-working-on-laptop-308.mp4`.
  - `docs/images/sanevideo-review-phone.jpg` from
    `outputs/appstore-real-captures/03-editor-phone.png` and
    `outputs/stock-source/mixkit-typing-on-cell-phone-4915.mp4`.
- Switched website image outputs from same-name PNG replacements to fresh JPEG
  filenames. This avoids Safari/Cloudflare showing cached stale images and
  reduces the three website proof assets from about `47 MB` total to under
  `1 MB` total in the Mini-generated deploy directory.
- Removed stale public proof files from `docs/images`, including the blank
  `sanevideo-recording-complete.png`. `scripts/generate_appstore_screenshots.swift`
  now includes those stale names in cleanup so they do not come back.
- Added `_redirects` entries for stale proof-asset URLs so cached/old HTML and
  direct image requests route to the new proof images instead of showing blank
  or repeated assets.
- Fixed a generator safety bug found during Mini verification:
  `scripts/generate_appstore_screenshots.swift` now validates every
  `realAppSource` before deleting generated outputs. Before this fix, missing
  Mini source captures could wipe `docs/images` and then fail.
- `docs/index.html`, `Screenshots/asset_sources.yml`,
  `Screenshots/appstore_screenshot_storyboard.yml`, and
  `ReleaseReadinessRegressionTests` now require varied real captures and block
  blank recording-complete proof, repeated woman-at-laptop fixtures, fake UI,
  and stale public image references.
- Local Browser verification after the refresh:
  - Desktop and mobile both reported no horizontal overflow, all three workflow
    images loaded, and no stale image references.
  - Screenshot receipts:
    `/Users/sj/Desktop/Screenshots/sanevideo-website-varied-full-desktop-20260614.png`
    and
    `/Users/sj/Desktop/Screenshots/sanevideo-website-varied-fresh-mobile-20260614.png`.
- Mini generator verification passed after syncing the real source captures:
  `swift scripts/generate_appstore_screenshots.swift` generated all three
  App Store screenshots and website JPEGs from real app captures.
- Live deployment completed twice via the canonical website-only path:
  `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project "$PWD" --website-only`.
  Final Cloudflare Pages deployment: `https://aa375a25.sanevideo-site.pages.dev`.
- Live verification:
  - `https://sanevideo.com/` references only
    `sanevideo-meeting-workflow.jpg`,
    `sanevideo-captions-transcribing.jpg`, and
    `sanevideo-review-phone.jpg`.
  - Old URLs including `/images/sanevideo-recording-complete.png`,
    `/images/sanevideo-actual-edit-workflow.png`,
    `/images/sanevideo-captions-transcribing.png`, and
    `/images/sanevideo-review-phone.png` return `301` to replacement JPEGs.
  - Browser receipt:
    `/Users/sj/Desktop/Screenshots/sanevideo-live-varied-workflow-desktop-20260614.png`.
- Mini focused XCTest attempts did not reach the assertion. Both result bundles
  reported `The test runner hung before establishing connection.`:
  `Test-SaneVideo-2026.06.14_01-03-20--0400.xcresult` and
  `Test-SaneVideo-2026.06.14_01-32-07--0400.xcresult`. Treat this as a
  Mini/Xcode runner blocker, not as a release-readiness assertion failure.
  Runtime-blocker screenshot was captured at
  `outputs/visual-audit-20260614/codex-shot-2026-06-14_01-35-15.png` and the
  Mini visual workspace was clean.

## 2026-06-14 App Store Availability Repair

- Root cause for SaneVideo being `READY_FOR_SALE` in App Store Connect but
  invisible publicly: app id `6770294375` had no app-level
  `/v1/apps/6770294375/appAvailabilityV2` resource. SaneClip, SaneSales, and
  SaneScan all had that resource; SaneVideo returned 404 before the repair.
- Repair applied on the Mini via App Store Connect API:
  `POST /v2/appAvailabilities` created availability for 175 territories with
  `availableInNewTerritories: true`.
- Important ASC API detail: inline `territoryAvailabilities` must use local IDs
  like `${territory-0}` in both `relationships.territoryAvailabilities.data`
  and `included`. Do not use the final encoded territory availability IDs for
  creation. For immediate availability with `preOrderEnabled: false`, omit
  `releaseDate`; ASC rejects releaseDate unless preorder is enabled.
- Verification: `/v1/apps/6770294375/appAvailabilityV2` now returns HTTP 200,
  `/v2/appAvailabilities/6770294375/relationships/territoryAvailabilities`
  reports total `175`, and all territory content statuses transitioned to
  `AVAILABLE` by `2026-06-14T04:05Z`.
- Public verification: iTunes bundle lookup
  `lookup?bundleId=com.sanevideo.app&country=us` returned `resultCount=1`,
  `trackName: SaneVideo`, `version: 1.0.1`, `kind: mac-software`, and App
  Store URL `https://apps.apple.com/us/app/sanevideo/id6770294375?mt=12&uo=4`.
  ID-only lookup still returned `resultCount=0` immediately after propagation,
  so use bundle-id lookup as the Mac listing verification signal.
- SaneProcess follow-up completed: `appstore_submit.rb` now creates missing
  app-level availability, and `SaneMaster.rb appstore_preflight` now blocks when
  app-level availability is missing or territory rows are not all `AVAILABLE`.

## 2026-06-13 Customer UI Receipt Mirror

- SaneVideo customer UI runner now writes the same receipt to both
  `.sane/customer_ui_action_receipt.json` and
  `outputs/customer_ui_action_receipt.json`. This fixes the SaneMaster
  Mini-route contract, which syncs/checks the `outputs/` receipt.
- Mini verification passed:
  - `ruby -c scripts/customer_ui_action_sweep.rb`
  - `./scripts/SaneMaster.rb test_mode --release --no-logs`
  - `./scripts/SaneMaster.rb customer_ui_sweep --json`
  - `./scripts/SaneMaster.rb customer_ui_contract --json --strict-visual --no-exit`
- Strict customer UI contract is green with receipt generated
  `2026-06-13T14:21:03Z`, action count `19`.
- Cross-product validation still blocks release on Q11 because Lemon Squeezy
  product `1087460`, variant `1703963` has no hosted
  `SaneVideo-1.0.1.zip` file. The ZIP is staged on the Mini at
  `~/Desktop/LemonSqueezy-Uploads/SaneVideo-1.0.1.zip`; the remaining action is
  dashboard-only.

## 2026-06-03 Website Proof Reset / Mini Access Restored

- User rejected the current SaneVideo website screenshots because they show fake/generated UI instead of the actual app. The local homepage remains paused/noindex until every public product screenshot is screenshot-level accurate.
- 2026-06-04 update: `docs/images/sanevideo-actual-edit-workflow.*`, `docs/images/sanevideo-recording.*`, `docs/images/sanevideo-captions-demo-pack.*`, `docs/images/sanevideo-export.*`, and `docs/images/sanevideo-magic-fix.*` were overwritten with real captured app screenshots from `outputs/mini-runtime-proof/` and `outputs/website-real-proof/`. The PNG hashes match the source proof captures. Do not treat the filename labels as feature-proof unless the visible UI state proves that specific feature; the full marketing page should stay paused until feature-specific captures exist for Transcript, Export, Thumbnail, Voiceover, Shorts, and the end-to-end workflow video.
- 2026-06-04 runtime-proof continuation: editor bootstrap now works through LaunchServices with real fixture arguments. Code changes:
  - `TestEnvironment.shouldOpenEditor` recognizes `SANEVIDEO_OPEN_EDITOR=1`, explicit `-test_asset_path` / `--test-asset-path=...`, and `--automation-transcript-path`.
  - `ProjectStore` and `ProjectState` use `TestEnvironment.shouldOpenEditor` instead of stale raw `OPEN_EDITOR` checks.
  - Main scene changed from `Window(...)` to `WindowGroup(...)` so the primary app window is created at launch.
  - Focused Mini test passed: `./scripts/SaneMaster.rb monitor_tests SaneVideo SaneVideoTests/ProjectEditingTests/testAutomationEnvironmentFlagsResolveExistingPaths 600`.
  - Clean Mini app-window proof: `outputs/visual-audit-20260603/01-editor-real-fixture.png` with receipt `outputs/visual-audit-20260603/receipt.json`. Logs showed `website-demo-video-call.mp4` imported, 5 transcript captions applied, a timeline clip selected, and the main window restored.
  - Full `./scripts/SaneMaster.rb verify` still exits red because `ReleaseReadinessRegressionTests.testAppStoreScreenshotStoryboardAndGeneratorCoverLaunchSellingPoints` expects the paused `docs/index.html` to reference `videos/sanevideo-hero-loop.mp4`, `images/sanevideo-magic-fix.jpg`, and `images/sanevideo-captions-demo-pack.jpg`. Keep this red until the full real proof set is ready; do not weaken the release gate.
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

- Older training, launch-readiness, and Mini incident details live in
  `ARCHITECTURE.md`, `DEVELOPMENT.md`, `.claude/research.md`, and git history.
  Keep this handoff focused on the active website-proof/runtime blockers above.

# Session Handoff — SaneVideo

**Last updated:** 2026-05-17

## Current State

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
  - Release pipeline note: first `release.sh --full --version 1.0 --deploy` attempt passed the public source-build guard after the SaneUI package fix, then stopped because the release script requires a clean git tree. Commit the release candidate, then rerun the same release command.

## Active Research Topics

- `.claude/research.md` topic `2026-05-16 Camera/Recording/Export V1 Runtime Proof` now includes 2026-05-17 release-readiness updates and should be graduated into `ARCHITECTURE.md`/`DEVELOPMENT.md` after the first published build.
- Current active blockers: clean-tree release commit before rerunning `release.sh --full --version 1.0 --deploy`, pending customer email, and Homebrew cask 404. App Store app/IAP/screenshot setup is no longer a hard blocker.

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

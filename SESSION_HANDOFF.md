# Session Handoff — SaneVideo

**Last updated:** 2026-04-25

## Current State

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

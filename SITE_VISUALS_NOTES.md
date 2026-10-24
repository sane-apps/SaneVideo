# SaneVideo site visuals: paused 2026-10-24, resume 2026-10-29

Branch `site-visuals-20261024` (Mini worktree `~/SaneApps/apps/SaneVideo/.claude/worktrees/site-visuals`). Not pushed, not deployed. Nothing on this branch is approved for the site yet.

## Done
- Art-commentary demo take, Kokoro narration, captures, 9.4 s loop, Create Shorts with real candidates, new og-image. Both site audits pass. Commits 1d98dd9 and 935f00a.
- Owner rejected the result on 2026-10-24: the creator is too small in the corner, the clip looks odd, and he saw "distorted PiP" and "dual captions". Treat every image and video on this branch as a draft to replace.

## Defect notes (checked so far)
- Dual captions: an app bug, not the source clip. `site-demo-art.mp4` carries no captions or text. When the editor preview is paused, it draws each caption twice: once at the top (the export render) and once at the bottom (the preview overlay). Evidence: `outputs/site-visuals-20261024/bugs/02-after.png`, `raw/22-after.png`.
- PiP: the composite bubble filter was `crop=690:460:585:255,scale=480:320`. Both are 3:2, and the source (Pexels 4994039) is 1920x1080 with square pixels and no rotation, so the filter does not stretch. Not yet checked: where the owner saw the distortion (app preview, the loop, or the Short), and a frame-by-frame face aspect check. Do both before any new capture.

## Files in ~/Movies/SaneVideo/ScreenshotKit
- `Tests/Assets/site-demo-art.mp4`: 63.4 s composite take (art viewer, small bubble, narration).
- `stock/pexels-4994039.mp4`: wide room shot. Do not use it again.
- `stock/pd-*.jpg`: six public-domain paintings (sources in `Screenshots/asset_sources.yml`).
- `voice/`: Kokoro am_michael narration (`narration.wav`, `lines.txt`, per-line wav and gap files). Keep it.
- `screen-bases/`: blurred-backdrop art frames. Being replaced.
- The close-up clip `pexels-4994033.mp4` was deleted. Re-download it: https://videos.pexels.com/video-files/4994033/4994033-hd_1920_1080_25fps.mp4 (5.2 MB, Tima Miroshnichenko, Pexels license).

## Next steps (owner plan, 2026-10-24)
1. Creator: the 4994033 close-up. Crop head and shoulders to 3:2, scale to cover then crop, never stretch, camera rig out of frame. Check face width/height against the original frame.
2. Bubble: the app's Large preset (PiPCameraWindow.PiPSize.large = 480x320 pt, scaled by recording width over screen width: about 610-640 px on a 1920 recording). Bottom-right, margin scaled the same way.
3. Screen: paintings full-frame in a plain browser or gallery window with normal window chrome, one at a time, simple cuts.
4. Before any build or app run: 3 option stills, about 1600 px wide, in `outputs/site-visuals-20261024/options/`: (a) gallery plus Large bubble bottom-right, (b) bubble bottom-left, (c) camera-forward if the app supports it. The owner picks one. Only then build, Clean Up, export and capture.
5. Never show top-placed or truncated captions. Capture caption states only while playing, or in the captions panel.

## App bugs for the backlog (evidence in outputs/site-visuals-20261024/bugs/)
1. Export burns captions at the top of the frame, and the preview adds a bottom copy when paused (`export-frames.jpg`, `02-after.png`).
2. After Clean Up, captions drop whole words that touch a cut (`export-captions-after-cleanup.srt`).
3. Create Shorts needs a source of at least 60 s, measured before cuts (`11-analyzed.png`).
4. Shorts have no captions. The TikTok export preset letterboxes 16:9 inside 9:16 (`tiktok-frames.jpg`).
5. README says Shorts go to Exports/Shorts; the code writes Movies/SaneVideo/Shorts.
6. Clicking a clip on the timeline did not select it. Unconfirmed; it may be the click method.

Tooling: mini-gui-run.sh `--close-window` leaves runner windows open (`mini-reclaim-automation-windows.sh --title X` closes them). Capture-agent video recording fails ("Mini screen recording failed").

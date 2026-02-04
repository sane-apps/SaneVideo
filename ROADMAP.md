# SaneVideo Feature Roadmap

**Last updated:** 2026-02-04

> **Purpose**: Track discussed features for future consideration. When user asks "what features have we discussed?" or similar, check this file.
>
> **Format**: Each entry includes context, feasibility assessment, and decision status.

---

## Discussed Features

### Voice Editing / Voice Commands

**Date Discussed**: 2025-12-29

**Concept**: Allow users to control the editor via voice commands ("split here", "delete selection", "undo") instead of keyboard/mouse.

**Current State**:
- WhisperKit is already integrated for caption generation
- However, it's **batch-only** (processes entire video files)
- No real-time microphone → transcription pipeline exists

**Feasibility Assessment**:

| Approach | Effort | Notes |
|----------|--------|-------|
| **Use existing WhisperKit** | High | Need to build mic capture → buffer → Whisper pipeline from scratch |
| **Use macOS SFSpeechRecognizer** | Low-Medium | Native, fast, no model download. Better for commands. |
| **Hybrid** | Medium | SFSpeechRecognizer for commands, WhisperKit for transcription |

**Recommended Path** (if pursued):
1. Start with macOS native `SFSpeechRecognizer` for voice commands
2. Push-to-talk activation (hotkey or button)
3. Small command vocabulary: split, delete, undo, redo, play, pause, mark in/out
4. Visual feedback showing recognized command before execution
5. Keep WhisperKit for its current purpose (caption generation)

**Market Context**:
- VEED.IO, Descript, InVideo AI, Captions all have natural language editing
- Most use typed text, not voice
- Descript's "Underlord" is closest competitor with plain language directions

**Decision**: Deferred — Not a quick win with current architecture. Revisit if user demand emerges or if mic capture infrastructure is needed for other features.

---

### Click Tracking Overlay (Screen Recording Enhancement)

**Date Discussed**: 2025-12-30

**Concept**: Display visual click indicators (ripple effects, cursor highlights) during screen recordings to help viewers follow along with tutorials and demos.

**Current State**:
- `ClickTrackingService.swift` exists with working click detection via CGEvent tap
- `ClickSample.swift` model stores click position, timestamp, and type (left/right/double)
- `RecordingEngine` can capture clicks during recording
- **Missing**: No overlay rendering in video output

**Feasibility Assessment**:

| Component | Status | Effort |
|-----------|--------|--------|
| Click detection | ✅ Complete | 0 |
| Click storage | ✅ Complete | 0 |
| Overlay rendering | ❌ Missing | ~100 lines |
| Style customization | ❌ Missing | ~50 lines |

**Recommended Path** (if pursued):
1. Add `ClickOverlayView` that renders ripple animations at click positions
2. Composite overlay onto video during export (CALayer or Metal)
3. User settings: ripple color, size, duration, sound effect
4. Consider adding cursor tracking for smoother trails

**Decision**: Deferred — Core functionality works, overlay rendering ~100 lines to complete. Good candidate for "polish" sprint.

---

### Smart Auto-Framing (Body/Hand Pose Detection)

**Date Discussed**: 2025-12-30

**Concept**: Automatically track and frame subjects in video using Vision framework's body and hand pose detection. Keep speaker centered, zoom to follow hand gestures.

**Current State**:
- `BodyPoseService.swift` exists with Vision framework integration
- Detects 19 body landmarks (nose, eyes, shoulders, elbows, wrists, hips, knees, ankles)
- Detects 21 hand landmarks per hand
- Converts normalized Vision coordinates to pixel coordinates
- **Missing**: No UI to trigger detection, no crop/zoom automation

**Feasibility Assessment**:

| Component | Status | Effort |
|-----------|--------|--------|
| Body detection | ✅ Complete | 0 |
| Hand detection | ✅ Complete | 0 |
| Subject tracking | ❌ Missing | ~80 lines |
| Auto-crop/zoom | ❌ Missing | ~70 lines |
| UI controls | ❌ Missing | ~50 lines |

**Recommended Path** (if pursued):
1. Add "Auto-Frame" toggle in clip inspector
2. Use body pose to calculate subject bounding box per frame
3. Smooth camera movement (avoid jitter) with interpolation
4. Apply crop/scale transform during export
5. Consider "face-only" vs "upper-body" vs "full-body" framing modes

**Decision**: Deferred — Detection works, needs ~150 lines for full feature. Valuable for talking-head videos and presentations.

---

## Template for New Entries

```markdown
### Feature Name

**Date Discussed**: YYYY-MM-DD

**Concept**: Brief description

**Current State**: What exists today that's relevant

**Feasibility Assessment**: Effort level and technical considerations

**Recommended Path**: If we were to do this, how would we approach it?

**Decision**: Approved / Deferred / Rejected + rationale
```

---

## Pre-Launch: Hardware Testing Plan

**Date Discussed**: 2025-12-31

**Problem**: Camera records at 15fps on Mac Studio despite 30fps config. Unknown if this is hardware-specific or widespread bug.

**Critical Question**: Does the app work reliably on different Mac hardware?

**Testing Strategy**:

| Approach | Pros | Cons |
|----------|------|------|
| Wife's M1 Mac | Free, trusted, immediate | Need signed build, limited sample |
| Friends (5-10 people) | Diverse hardware, real feedback | Need installer, support burden |
| Open source repo | Free testing, contributors | **Competitors clone Magic Fix, hard to close** |
| Paid beta service (BetaFamily) | Professional, diverse hardware | Costs money |
| TestFlight-style closed beta | Controlled, NDA possible | Need distribution infrastructure |

**Recommended Path**:
1. Build Release archive with diagnostic logging
2. Export unsigned .app (right-click → Open bypasses Gatekeeper)
3. Test on wife's M1 Mac first - check if 15fps issue exists
4. If M1 works at 30fps → Mac Studio specific (document limitation)
5. If M1 also 15fps → app bug, needs deeper investigation
6. Recruit 3-5 friends with different Macs for broader testing
7. Create simple feedback form (Google Form?) for hardware specs + issues

**Diagnostic Mode Needed**:
- Log camera model, supported formats, configured FPS, actual FPS
- Log mic model, sample rate, buffer sizes
- Write to visible file (~/Desktop/SaneVideo_Diagnostics.txt)
- Show hardware summary in Settings or Help menu

**DO NOT open source** — Magic Fix audio pipeline is your differentiator.

**Decision**: Next action item when ready to test

---

## Quick Reference

| Feature | Status | Effort | Notes |
|---------|--------|--------|-------|
| Voice Commands | Deferred | Medium-High | Use native SFSpeechRecognizer if revisited |
| Click Tracking Overlay | Deferred | Low (~100 lines) | Detection works, needs overlay rendering |
| Smart Auto-Framing | Deferred | Medium (~150 lines) | Body/hand pose detection works, needs UI + crop automation |
| ML Export Effects | Deferred | High (~300 lines) | MLEffectsService exists, needs export pipeline integration |


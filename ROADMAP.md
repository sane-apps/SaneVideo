# SaneVideo Feature Roadmap

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

## Quick Reference

| Feature | Status | Effort | Notes |
|---------|--------|--------|-------|
| Voice Commands | Deferred | Medium-High | Use native SFSpeechRecognizer if revisited |


# Audio Timeline Synchronization

> When to use: Working with Magic Fix, audio enhancement, clip timing, or fixing A/V desync

---

## What This Is (Plain English)

Audio sync is the #1 source of video editing bugs. When you process audio (remove silence, enhance, resample), the timing can drift from the original video. This skill covers:

- **Magic Fix** - Automatic silence/filler removal
- **Audio Enhancement** - Voice isolation, noise reduction
- **Sample Rate Conversion** - 44.1kHz vs 48kHz
- **Timeline Composition** - Building final export

The golden rule: **Always use original media timing, never processed media duration.**

---

## Key Concepts

### CMTime - The Universal Currency

All timing in AVFoundation uses CMTime:

```swift
let oneSecond = CMTime(seconds: 1.0, preferredTimescale: 600)
let thirtyFrames = CMTime(value: 30, timescale: 600)  // 30/600 = 0.05 seconds

// Arithmetic
let total = time1 + time2
let half = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)

// Comparison
if time1 < time2 { ... }
if CMTIME_IS_VALID(time) { ... }
```

### Sample Rate vs Frame Rate

| Domain | Rate | Duration Unit |
|--------|------|---------------|
| **Video** | 30/60 fps | CMTime (frames) |
| **Audio** | 44100/48000 Hz | Samples |

```swift
// Convert between them
let audioSamples = Int(duration.seconds * 48000)
let videoDuration = CMTime(seconds: Double(samples) / 48000, preferredTimescale: 600)
```

---

## The Desync Bug Pattern

### What Happens

1. Original clip: 10.0 seconds video + 10.0 seconds audio
2. Magic Fix removes 2 seconds of silence from audio
3. Enhanced audio: 8.0 seconds
4. Export uses enhanced audio duration → Video gets cut at 8 seconds!

### The Fix (clip.duration, not enhanced.duration)

```swift
// ❌ WRONG - uses processed audio duration
func buildComposition(clip: VideoClip, enhancedAudio: AVAsset) {
    let audioDuration = enhancedAudio.duration  // 8 seconds (WRONG!)
    try videoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: audioDuration),
        of: originalVideoTrack,
        at: insertionPoint
    )
}

// ✅ CORRECT - uses original clip duration
func buildComposition(clip: VideoClip, enhancedAudio: AVAsset) {
    let originalDuration = clip.duration  // 10 seconds (CORRECT!)
    try videoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: originalDuration),
        of: originalVideoTrack,
        at: insertionPoint
    )
    // Audio track uses its own duration - timeline handles mismatch
}
```

---

## Magic Fix Implementation

### Architecture

```
Original Clip
     ↓
┌─────────────────┐
│ Transcribe      │ → WhisperKit segments with timestamps
│ (WhisperKit)    │
└─────────────────┘
     ↓
┌─────────────────┐
│ Detect Ranges   │ → Silence + filler word ranges
│ (SmartFiller)   │
└─────────────────┘
     ↓
┌─────────────────┐
│ Mark Removed    │ → clip.removedRanges: [CMTimeRange]
│ (Non-destructive)│
└─────────────────┘
     ↓
Export (applies removals)
```

### Non-Destructive Editing

Never modify original media. Store removal ranges:

```swift
struct VideoClip {
    let asset: AVAsset
    let originalDuration: CMTime
    var removedRanges: [CMTimeRange] = []  // Magic Fix stores here

    var effectiveDuration: CMTime {
        let removed = removedRanges.reduce(CMTime.zero) { $0 + $1.duration }
        return originalDuration - removed
    }
}
```

### Applying Removals at Export

```swift
func buildExportComposition(clip: VideoClip) throws -> AVMutableComposition {
    let composition = AVMutableComposition()

    // Calculate kept ranges (inverse of removed)
    let keptRanges = calculateKeptRanges(
        total: clip.originalDuration,
        removed: clip.removedRanges
    )

    var insertionPoint = CMTime.zero
    for range in keptRanges {
        try composition.insertTimeRange(range, of: clip.asset, at: insertionPoint)
        insertionPoint = insertionPoint + range.duration
    }

    return composition
}

func calculateKeptRanges(total: CMTime, removed: [CMTimeRange]) -> [CMTimeRange] {
    // Sort and merge overlapping ranges
    let sorted = removed.sorted { $0.start < $1.start }
    let merged = mergeOverlapping(sorted)

    // Invert to get kept ranges
    var kept: [CMTimeRange] = []
    var cursor = CMTime.zero

    for range in merged {
        if cursor < range.start {
            kept.append(CMTimeRange(start: cursor, end: range.start))
        }
        cursor = range.end
    }

    if cursor < total {
        kept.append(CMTimeRange(start: cursor, duration: total - cursor))
    }

    return kept
}
```

---

## Audio Enhancement Gotchas

### AUSoundIsolation Offline Bug

Apple's voice isolation doesn't work in offline mode:

```swift
// ❌ WRONG - hangs forever in offline rendering
let isolationNode = AVAudioUnitEffect(audioComponentDescription: auSoundIsolation)
engine.attach(isolationNode)
// ... offline render ...

// ✅ CORRECT - skip isolation for offline
func enhanceAudio(isOffline: Bool) async throws -> AVAsset {
    if isOffline {
        // Use only noise reduction, skip voice isolation
        return try await applyNoiseReduction(asset)
    } else {
        return try await applyFullEnhancement(asset)
    }
}
```

### scheduleSegment Await Bug

`await scheduleSegment()` waits for PLAYBACK completion, not scheduling:

```swift
// ❌ WRONG - blocks until audio finishes playing
await playerNode.scheduleSegment(
    file,
    startingFrame: 0,
    frameCount: frameCount,
    at: nil
)

// ✅ CORRECT - use completion handler, don't await
playerNode.scheduleSegment(
    file,
    startingFrame: 0,
    frameCount: frameCount,
    at: nil,
    completionHandler: nil  // Explicit nil, no waiting
)
```

---

## Sample Rate Handling

### The 44.1kHz Problem

AAC encoding often uses 44.1kHz, but video is typically 48kHz:

```swift
func validateSampleRates(video: AVAsset, audio: AVAsset) throws {
    guard let videoAudio = video.tracks(withMediaType: .audio).first,
          let processedAudio = audio.tracks(withMediaType: .audio).first else {
        throw SyncError.missingAudioTrack
    }

    let originalRate = videoAudio.naturalTimeScale  // e.g., 48000
    let processedRate = processedAudio.naturalTimeScale  // e.g., 44100

    if originalRate != processedRate {
        // Duration will differ! 10 sec @ 48kHz ≠ 10 sec @ 44.1kHz
        log.warning("Sample rate mismatch: \(originalRate) vs \(processedRate)")
    }
}
```

### Resampling Correctly

```swift
func resampleAudio(asset: AVAsset, to targetRate: Double) async throws -> AVAsset {
    let reader = try AVAssetReader(asset: asset)
    let writer = try AVAssetWriter(outputURL: tempURL, fileType: .m4a)

    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: targetRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true
    ]

    // Read → Resample → Write pipeline
    // ...
}
```

---

## Testing Sync

### Automated Sync Test

```swift
@Test func magicFixMaintainsSync() async throws {
    let clip = try await loadTestClip("test_with_silence.mp4")
    let originalDuration = clip.duration

    // Apply Magic Fix
    let processed = try await magicFixService.process(clip)

    // Video duration must NOT change
    #expect(processed.videoDuration == originalDuration)

    // Only audio has removals
    #expect(processed.removedRanges.count > 0)
    #expect(processed.effectiveAudioDuration < originalDuration)
}
```

### Manual Verification

```bash
# Check durations match
ffprobe -v error -show_entries format=duration -of csv=p=0 video.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 audio.m4a

# Visual sync check - export first and last frame
ffmpeg -i export.mp4 -vf "select=eq(n\,0)" -vframes 1 first.png
ffmpeg -sseof -1 -i export.mp4 -vframes 1 last.png
```

---

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Audio ends early | Used enhanced duration | Use `clip.duration` |
| Lip sync drift | Sample rate mismatch | Resample to match |
| Silence gaps | Time range calculation error | Check `mergeOverlapping` |
| Export hangs | `await scheduleSegment` | Use completionHandler:nil |
| Voice isolation hangs | Offline mode + AUSoundIsolation | Skip isolation offline |

---

## SaneVideo Files Reference

| File | Purpose |
|------|---------|
| `Services/Audio/AudioTrackBuilder.swift` | Timeline composition |
| `Services/Audio/SaneAudioEnhancementService.swift` | Voice isolation, noise reduction |
| `Services/Captions/SmartFillerDetector.swift` | "Um", "uh" detection |
| `Services/Captions/WhisperKitService.swift` | Transcription with timestamps |
| `Core/Models/VideoClip.swift` | `removedRanges` storage |
| `ProjectState+SmartFeatures.swift` | Magic Fix orchestration |

---

*~220 lines • Last updated: 2026-01-15*

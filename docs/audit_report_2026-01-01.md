# Brutal Codebase Audit Report

> **Date**: 2026-01-01
> **Status**: FINAL (Brutal Pass Completed)
> **Verdict**: The codebase is functional but fragile. It relies on extensive "cheating" to bypass Swift 6 strict concurrency, uses "sleep" to manage hardware timing, and employs defensive coding to mask deep logic bugs.

---

## 1. ☠️ The "Sleep Hacking" Epidemic
The application relies on `Task.sleep` to coordinate complex asynchronous hardware states. This is **non-deterministic** and guaranteed to fail on slower machines or under load.
- **Camera Startup**: `CameraManager` sleeps 0.2s to "stabilize" the session.
- **Screen Picker**: `ScreenRecorder` loops with 0.5s sleeps to wait for the user.
- **Audio Service**: sleeps 0.2s after starting the capture session.
- **File Loading**: `ProjectFileManager` retries with exponential backoff sleeps.

## 2. 🛡️ Concurrency "Cheating"
To silence Swift 6 strict concurrency warnings, the codebase massively abuses unsafe constructs. This negates the safety benefits of Swift 6.
- **`UncheckedBox`**: Used to wrap `AVAssetImageGenerator` and other classes to force them to be `Sendable`. This is a time bomb if those objects are not actually thread-safe.
- **`nonisolated(unsafe)`**: **40+ instances** found. Used on `WhisperKit`, `AVAuthStatus`, and mostly for `Task` storage in Observables. This bypasses compile-time safety checks.
- **`Task.detached`**: pervasive use for "utility" work breaks actor context propagation.

## 3. 🕸️ Architectural Fragility
- **Service Container Main-Thread Block**: `ServiceContainer.init()` initializes **ALL** 40+ services on the Main Actor synchronously. This will cause significant app launch lag.
- **Lazy Loading Risk**: `appState` is `lazy`. `lazy` properties are **not thread-safe**. If a background task accesses `ServiceContainer.shared.appState` first, it could crash.
- **Memory Management Theater**: `MemoryManager` clears caches (good) but does not actively release heavy `AVAsset` or `AVPlayerItem` resources managed by `AVFoundation`.

## 4. 🔇 Error Swallowing
- **Queue Dropping**: `ErrorPresenter` has a fixed-size queue of 10. If 11 errors occur (e.g., during a batch processing failure), the newest ones are **silently dropped** if not critical.
- **Toast Replacement**: `ToastManager`'s queue logic replaces the *last* queued item if a new one comes in while busy, meaning users might miss intermediate status updates.

## 5. 👻 Defensive Coding (Masking Bugs)
The code "fixes" invalid data instead of preventing it.
- **Negative Timestamps**: `ProjectFileManager` has logic to clamp negative start times to zero on load. This means `TimelineEngine` is producing corrupt clip data.
- **Undo State**: `ProjectState` validates the timeline after every undo/redo, implying that the undo stack frequently contains invalid states.

## 6. 🔊 Audio Quality
- **Limiter Bypassed**: The `AudioLimiter` is explicitly commented out in `CompositionBuilder`. Expect clipping/distortion in exports.
- **Desync**: `AudioTrackBuilder` admits that specialized audio files have different durations than video, leading to potential desync.

## Recommendations
1.  **Stop Sleeping**: Replace all `Task.sleep` logic with `KVO`, `NotificationCenter`, or delegate callbacks. This is the #1 stability risk.
2.  **Fix the Init**: Move service initialization to a background queue or make it truly lazy/async to unblock app launch.
3.  **Audit `UncheckedBox`**: Manually verify thread safety of every wrapped object. `AVAssetImageGenerator` is generally thread-safe, but others may not be.
4.  **Enable the Limiter**: Fix the `AudioLimiter` or use an `MTAudioProcessingTap` that works.
5.  **Remove Defensive Patches**: Add fatal errors (in debug) where negative timestamps occur to find the *source* of the bug.

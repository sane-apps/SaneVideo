# SaneVideo for macOS

**The Professional Video Recording & Editing App for macOS**

SaneVideo is a native macOS video recording and editing app. No subscriptions. Local recording, editing, and export run on your Mac.

**Last updated:** 2026-10-17
**Current direct release:** 1.1.0

---

## Why SaneVideo?

Video editing shouldn't require a subscription, a PhD, or surrendering your privacy.

Most tools fall into two traps: **bloated professionals** that overwhelm everyday creators, or **subscription services** that rent you tools while harvesting your data. SaneVideo takes a different path.

| | The Problem | The Sane Way |
|---|---|---|
| **Power** | Cloud-dependent, vendor-controlled | Your video, your Mac, your rules |
| **Love** | Built to extract (subscriptions, upsells) | Built to serve. No dark patterns. |
| **Sound Mind** | Feature bloat, cluttered interfaces | One thing done well. Calm UI. |

> *"For God has not given us a spirit of fear, but of power and of love and of a sound mind."*
> — 2 Timothy 1:7

**Local-First Video Workflow**

SaneVideo is free, with 100% Transparent Code (PolyForm Shield). Setup stays. Every recording and edit tool stays unlocked. Donate only if you want to support it.

---

## Download

**[Download SaneVideo](https://sanevideo.com)** or clone the source. Current release: **1.1.0**. The app is signed, notarized, and built for local screen, camera, and microphone recording without uploading your footage to SaneApps servers.

Support: [GitHub Sponsors](https://github.com/sponsors/MrSaneApps) · Contribute: https://github.com/sane-apps/SaneVideo

---

> **For Developers & AI Agents**: [DEVELOPMENT.md](DEVELOPMENT.md) is the SOP (Single Source of Truth).

---

## ✨ Features

### Recording

- **Full Screen Recording**: Capture your entire screen in high resolution
- **Window Recording**: Select specific windows to record
- **Camera Bubble**: Your camera in a movable bubble over the screen, or full frame on its own; switch between them mid-take
- **Microphone Capture**: Record narration or meetings locally on your Mac
- **Keyboard Controls**: `⌥⌘R` starts and stops recording from any app; `⌥⌘P` pauses while recording

### Editing

- **Professional Timeline**: Industry-standard timeline with:
  - Drag & drop video import from Finder
  - Scrubbing and precise frame navigation
  - Keyboard shortcuts (J-K-L for playback, Space for play/pause)
  - Split clips (⌘B), ripple delete, trim handles
  - Visual playhead with grid overlay

- **Framing, Background and Effects**: Crop and zoom, blur or replace the background behind you, and color effects (Noir, Sepia, Vignette and more) in the inspector

- **Clean Up** (one click, on your Mac):
  - **Silence Removal**: Cuts the pauses where nobody talks
  - **Filler Words**: Cuts "um", "uh" and stutters (Parakeet speech model, downloaded once)
  - **Captions**: On-device transcript; exports write a matching `.srt` for YouTube
  - Every cut can be undone

### Export

- **YouTube-ready Export**: Matches your recording's size and frame rate
- **Shorts, GIF, Thumbnail, Transcript PDF**: From the Export menu
- **Saved to Movies/SaneVideo/Exports**: Revealed in Finder when done
- **No Cloud Handoff**: Export locally when the edit is ready

### UI/UX Polish

- **Native macOS Design**:
  - SF Symbols throughout
  - Vibrancy and transparency effects
  - Proper dark mode support
  - Rounded corners and modern aesthetics
  
- **Smooth Animations**:
  - SwiftUI transitions
  - Pulsing recording indicator
  - Responsive hover states

---

## 🎯 System Requirements

**Minimum Requirements:**
- **macOS 26** or later
- **Apple Silicon** (arm64) only - Intel Macs not supported
- **8GB RAM** minimum (16GB recommended for 4K editing)
- About 600 MB of disk for the speech model, downloaded the first time you use Clean Up or captions


---

## 🚀 Quick Start

### First Run

1. Launch `SaneVideo.app`
2. Grant permissions when prompted:
   - **Camera**: For webcam recording
   - **Microphone**: For audio capture
   - **Screen Recording**: For screen capture

### Recording

- **Keyboard**: `⌘N` for a new recording; `⌥⌘R` starts and stops from any app while the recorder is open
- **Window**: Click Record in the recorder bar at the bottom

### Importing Videos

- Drag any video file onto the main window
- Or: Click Import button (⌘I)
- Or: File → Import Video

### Editing

- Press **Clean Up** in the inspector to cut silences and filler words
- Trim and split on the timeline (⌘B splits at the playhead); every edit can be undone
- Browse projects, clips and the transcript in the left sidebar

### Exporting

- Click **Export** (⌘E). The preset matches your recording.
- The file lands in `Movies/SaneVideo/Exports`, with a matching `.srt` when the project has captions.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌥⌘R` | Start / stop recording (any app, while the recorder is open) |
| `⌥⌘P` | Pause / resume (while recording) |
| `⌘N` | New Recording |
| `⌘I` | Import Video |
| `Space` | Play/Pause |
| `←` | Previous Frame |
| `→` | Next Frame |
| `J` | Play backward |
| `K` | Pause |
| `L` | Play forward |
| `⌘B` | Split Clip at Playhead |
| `Delete` | Delete Selected Clip |

---

## 🏗️ Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md).

**Key Technologies**: SwiftUI, AVFoundation, ScreenCaptureKit, Core Image, Vision, FluidAudio (Parakeet speech model)

---

## 🔒 Privacy & Security

SaneVideo is designed with privacy first:

- **App Sandbox** enabled with minimal permissions
- **Hardened Runtime** for security
- **Local processing**: Recording, editing, speech recognition and export happen on your Mac
- **No uploads**: Your recordings never leave your Mac unless you share a file yourself
- **Network use**: update checks, anonymous aggregate app counts, and a one-time download of the speech model (about 600 MB)

### Permissions Explained

- **Camera**: Only used when you explicitly start camera recording
- **Microphone**: Only active during recording sessions
- **Screen Recording**: Required for screen capture. macOS controls this in System Settings and may require restarting SaneVideo after approval.

---

## 📁 File Storage

- **Projects**: `~/Movies/SaneVideo/Projects/`
- **Recordings**: `~/Movies/SaneVideo/Recordings/`
- **Exports**: `~/Movies/SaneVideo/Exports/` (plus `Shorts/` for vertical clips)

All files remain on your local machine. No cloud storage required.

---

**⚠️ Refer to [DEVELOPMENT.md](DEVELOPMENT.md) for the authoritative build workflow.**

---

## 🛠️ Developer Notes (Build/Test)

- **Build environment**: Requires **macOS + Xcode** (the test runner uses `xcodebuild`). Linux environments can’t run the full verification workflow.
- **One command workflow**: Use `./scripts/SaneMaster.rb verify` (don’t run raw `xcodebuild`).
- **Test assets** live in `Tests/Assets/` (e.g., `test_video.mp4`, `test_silence.mp4`).

## 🎨 Design Philosophy

Built on the three pillars of **Power**, **Love**, and **Sound Mind**:

- **Power** (Agency): Native macOS, on-device processing, no lock-in. You control your tools.
- **Love** (Service): Solves real problems for real creators. No dark patterns, no extraction.
- **Sound Mind** (Clarity): Clean interface, one-click Clean Up, calm experience. Reduces noise.

---

## Current Scope

- ✅ Screen + Camera Recording
- ✅ Timeline Editing
- ✅ Clean Up (silence and filler-word removal)
- ✅ Captions, transcript and `.srt` export
- ✅ Export, Shorts, GIF and thumbnails

---

## 📄 License

[PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0) — free for any use except building a competing product. See [LICENSE](LICENSE)

---

## 🙏 Credits

Built with passion for the macOS creator community.

**Technologies**:

- SwiftUI (Apple)
- AVFoundation (Apple)
- Metal (Apple)
- Core Image (Apple)
- ScreenCaptureKit (Apple)

---

## 📞 Support

For issues or questions:

- Check the built-in Help menu
- Use Settings → About → Report a Bug to copy diagnostics for support
- Review keyboard shortcuts (above)
- Ensure all permissions are granted in System Settings → Privacy & Security
- Email hi@saneapps.com for private reports

---

**Keep your head. Stay Sane.**

*Built for a Sound Mind | Local-First Video Workflow | 0% Fear*

## Third-Party Notices

Third-party attributions are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

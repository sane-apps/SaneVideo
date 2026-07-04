# SaneVideo for macOS

**The Professional Video Recording & Editing App for macOS**

SaneVideo is a native macOS video recording and editing app. No subscriptions. Local recording, editing, and export run on your Mac.

**Last updated:** 2026-06-08
**Current public testing release:** 1.0.1

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

Pro is free for 14 days. After that, Pro is required and remains a $14.99 one-time upgrade.

---

> **For Developers & AI Agents**: [DEVELOPMENT.md](DEVELOPMENT.md) is the SOP (Single Source of Truth).

---

## ✨ Features

### Recording

- **Full Screen Recording**: Capture your entire screen in high resolution
- **Window Recording**: Select specific windows to record
- **Camera Overlay**: Front camera support for picture-in-picture style recordings
- **Keyboard Controls**: Start a new recording with `⌘N`; direct builds may also expose `⌥⌘R` global recording where macOS permissions allow it

### Editing

- **Professional Timeline**: Industry-standard timeline with:
  - Drag & drop video import from Finder
  - Scrubbing and precise frame navigation
  - Keyboard shortcuts (J-K-L for playback, Space for play/pause)
  - Split clips (⌘B), ripple delete, trim handles
  - Visual playhead with grid overlay

- **Real-Time Filters** (120fps Metal-accelerated):
  - **Natural**: Subtle color correction and sharpening
  - **Cinematic**: Desaturated look with vignette and blue tones
  - **Vintage**: Warm sepia with film grain and strong vignette

- **Magic Fix** (AI-Powered):
  - **Silence Removal**: Automatically cuts silent pauses
  - **Filler Word Detection**: Identifies "um", "uh", "like"
  - **Smart Cleanup**: Non-destructive edits you can refine

### Export

- **HEVC 4K Export**: Smart bitrate encoding for optimal file size
- **Progress Tracking**: Real-time export progress
- **Desktop Save**: Quick access to exported videos

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
- **macOS 15.0 (Sequoia)** or later
- **Apple Silicon** (arm64) only - Intel Macs not supported
- **8GB RAM** minimum (16GB recommended for 4K editing)
- **AI features** require macOS 26.0+ (FoundationModels/Translation); core recording/editing works on 15.0+

> **Note**: SaneVideo is optimized for newer macOS features when available, but the core app runs on macOS 15.0+.


---

## 🚀 Quick Start

### First Run

1. Launch `SaneVideo.app`
2. Grant permissions when prompted:
   - **Camera**: For webcam recording
   - **Microphone**: For audio capture
   - **Screen Recording**: For screen capture

### Recording

- **Keyboard**: Press `⌘N`
- **Window**: Click the Record button in the toolbar

### Importing Videos

- Drag any video file onto the main window
- Or: Click Import button (⌘I)
- Or: File → Import Video

### Editing

- Select clips in the Media Library (left sidebar)
- View in the player (center)
- Arrange on timeline (bottom)
- Apply filters with the segmented control
- Split clips at playhead position (⌘B)

### Exporting

- Click Export button
- Choose destination
- Wait for progress to complete

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌥⌘R` | Toggle Recording in direct builds where global hotkey support is available |
| `⌘N` | New Recording |
| `⌘I` | Import Video |
| `Space` | Play/Pause |
| `←` | Previous Frame |
| `→` | Next Frame |
| `J` | Rewind (hint) |
| `K` | Pause (hint) |
| `L` | Fast Forward (hint) |
| `⌘B` | Split Clip at Playhead |
| `Delete` | Delete Selected Clip |

---

## 🏗️ Architecture

See [DEVELOPMENT.md](DEVELOPMENT.md) for full architecture details.

**Key Technologies**: SwiftUI, AVFoundation, ScreenCaptureKit, Metal, Core Image, Vision, Core ML

---

## 🔒 Privacy & Security

SaneVideo is designed with privacy first:

- **App Sandbox** enabled with minimal permissions
- **Hardened Runtime** for security
- **Local Processing**: All video processing happens on your Mac
- **Local processing**: Recording, editing, and local export happen on your Mac
- **No project upload by default**: Video files stay local unless you explicitly choose an external workflow
- **Network is optional and scoped**: Updates, licensing, privacy-safe aggregate app counts, and optional integrations may use the network

### Permissions Explained

- **Camera**: Only used when you explicitly start camera recording
- **Microphone**: Only active during recording sessions
- **Screen Recording**: Required for screen capture. macOS controls this in System Settings and may require restarting SaneVideo after approval.

---

## 📁 File Storage

- **Projects**: `~/Movies/SaneVideo/Projects/`
- **Recordings**: `~/Movies/SaneVideo/Recordings/`
- **Exports**: `~/Desktop/` by default, with an app-storage fallback if Desktop is unavailable

All files remain on your local machine. No cloud storage required.

---

**⚠️ Refer to [DEVELOPMENT.md](DEVELOPMENT.md) for the authoritative build workflow.**

---

## 🛠️ Developer Notes (Build/Test)

- **Build environment**: Requires **macOS + Xcode** (the test runner uses `xcodebuild`). Linux environments can’t run the full verification workflow.
- **One command workflow**: Use `./scripts/SaneMaster.rb verify` (don’t run raw `xcodebuild`).
- **Test assets**:
  - Generate lightweight media fixtures with `./scripts/SaneMaster.rb gen_assets` (requires `ffmpeg`).
  - Assets live in `Tests/Assets/` (e.g., `test_video.mp4`, `test_silence.mp4`).

## 🎨 Design Philosophy

Built on the three pillars of **Power**, **Love**, and **Sound Mind**:

- **Power** (Agency): Native macOS, on-device processing, no lock-in. You control your tools.
- **Love** (Service): Solves real problems for real creators. No dark patterns, no extraction.
- **Sound Mind** (Clarity): Clean interface, 120fps Metal filters, calm experience. Reduces noise.

---

## Current Scope

- ✅ Screen + Camera Recording
- ✅ Timeline Editing
- ✅ Real-time Filters
- ✅ HEVC Export
- [x] Magic Fix (Silence & Filler Removal)

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

Third-party open-source attributions are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

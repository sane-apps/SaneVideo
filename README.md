# SaneVideo for macOS

**The Professional Video Recording & Editing App for macOS**

SaneVideo is a modern,native macOS application built with SwiftUI and AVFoundation for recording, editing, and exporting high-quality videos. Designed for creators who want powerful tools with an elegant, native interface.

> **🚨 FOR DEVELOPERS & AI AGENTS 🚨**
> **Consolidated SOP**: See [DEVELOPMENT.md](DEVELOPMENT.md) for **ALL** build rules, AI constraints, architecture, style guides, and tools.
> **DO NOT** look elsewhere.

---

## ✨ Features

### Recording

- **Full Screen Recording**: Capture your entire screen in high resolution
- **Window Recording**: Select specific windows to record
- **Camera Overlay**: Front camera support for picture-in-picture style recordings
- **Global Hotkey**: Press `⌥⌘R` anywhere to start/stop recording instantly
- **Menu Bar Integration**: Always-accessible menu bar icon with status indicators
  - Black camera icon when idle
  - Pulsing red dot while recording
  - Real-time recording duration display

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

- **Auto Enhance** (Core ML):
  - One-click color correction
  - Intelligent denoising
  - Automatic brightness/exposure adjustment

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

## 🎯 Requirements

- macOS 26.2 (Tahoe) or later
- Apple Silicon (M1/M2/M3/M4) only
- 8GB RAM minimum (16GB recommended for 4K editing)

---

## 🚀 Quick Start

### First Run

1. Launch `SaneVideo.app`
2. Grant permissions when prompted:
   - **Camera**: For webcam recording
   - **Microphone**: For audio capture
   - **Screen Recording**: For screen capture

### Recording

- **Menu Bar**: Click the SaneVideo icon → "New Recording"
- **Keyboard**: Press `⌘N` or use global hotkey `⌥⌘R`
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
| `⌥⌘R` | Toggle Recording (Global)  |
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
- **No Telemetry**: Zero data collection or analytics
- **No Network**: App works completely offline

### Permissions Explained

- **Camera**: Only used when you explicitly start camera recording
- **Microphone**: Only active during recording sessions
- **Screen Recording**: Required for screen capture, granted per-session by macOS

---

## 📁 File Storage

- **Projects**: `~/Movies/SaneVideo/Projects/`
- **Recordings**: `~/Movies/SaneVideo/Recordings/`
- **Exports**: `~/Desktop/` (configurable)

All files remain on your local machine. No cloud storage required.

---

**⚠️ Refer to [DEVELOPMENT.md](DEVELOPMENT.md) for the authoritative build workflow.**

---

## 🎨 Design Philosophy

SaneVideo embraces these principles:

1. **Native First**: Feels like it was made by Apple
2. **Performance**: 120fps real-time filters, instant UI response
3. **Simplicity**: Complex features, simple interface
4. **Privacy**: Your data stays on your Mac
5. **Quality**: 4K HEVC exports with professional-grade filters

---

## 🗺️ Roadmap

### Phase 1 (Current)

- ✅ Screen + Camera Recording
- ✅ Timeline Editing
- ✅ Real-time Filters
- ✅ HEVC Export

### Phase 2 (Current)

- [x] Magic Fix (Silence & Filler Removal)
- [ ] Audio timeline tracks
- [ ] Transitions between clips
- [ ] Text overlays and titles
- [ ] Keyframe animations
- [ ] Multi-track editing

### Phase 3 (Future)

- [ ] Motion tracking
- [ ] Green screen removal
- [ ] Advanced color grading
- [ ] Plugin system
- [ ] Collaboration features

---

## 📄 License

Proprietary - © 2025 SaneVideo

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
- Review keyboard shortcuts (above)
- Ensure all permissions are granted in System Settings → Privacy & Security

---

**Made with ❤️ for macOS**

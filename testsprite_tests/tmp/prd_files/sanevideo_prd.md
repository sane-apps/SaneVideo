# SaneVideo - Product Requirements Document

## Overview
SaneVideo is a professional-grade, native macOS video recording and editing application designed for content creators, educators, and professionals who need to capture, edit, and export high-quality screen recordings with camera overlays.

## Target Platform
- **OS**: macOS 15.1+ (Sequoia)
- **Architecture**: Apple Silicon (M1/M2/M3/M4)
- **Distribution**: Direct / Mac App Store

## Core Features

### 1. Screen Recording
- **Full Screen Capture**: Capture entire screen using ScreenCaptureKit
- **Window Selection**: Target specific windows for recording
- **Camera Overlay**: Picture-in-picture camera feed during recording
- **Global Hotkey**: Alt+Cmd+R to start/stop recording from anywhere
- **Menu Bar Integration**: Status indicator and quick controls
- **Countdown Timer**: 3-second countdown before recording starts
- **Audio Capture**: System audio and microphone input with toggle

### 2. Video Editing (Timeline)
- **Timeline Editor**: Professional drag-and-drop timeline interface
- **Playback Controls**: J-K-L keyboard shortcuts for playback
- **Scrubbing**: Frame-by-frame navigation with visual playhead
- **Clip Operations**:
  - Split clips (Cmd+B)
  - Trim start/end
  - Ripple delete
- **Waveform Visualization**: Audio waveform display on timeline
- **Caption Overlay**: Add and style captions on video

### 3. Caption Generation
- **Auto-Transcription**: Whisper AI integration for automatic captions
- **Caption Editing**: Edit, timing adjust, and style captions
- **Caption Styles**: Customizable font, color, position, background

### 4. Export
- **Video Export**: HEVC 4K export with smart bitrate
- **Progress Tracking**: Real-time export progress display
- **PDF Reports**: Generate PDF from project
- **YouTube Integration**: Direct upload capability
- **Thumbnail Generation**: Auto-generate video thumbnails

### 5. Project Management
- **Project Persistence**: Save/load projects with full state
- **Recent Projects**: Quick access to recent work
- **Auto-Save**: Automatic project saving

### 6. User Experience
- **Onboarding**: First-time user guide
- **Settings**: User preferences management
- **Keyboard Shortcuts**: Comprehensive keyboard navigation
- **Accessibility**: VoiceOver and accessibility support

## Technical Requirements

### Performance
- 120fps filter rendering with Metal GPU acceleration
- Efficient memory management for large recordings
- Disk space monitoring (200MB minimum required)

### Privacy & Security
- App Sandbox enabled
- User-gated permissions for Screen Recording, Camera, Microphone
- No telemetry or network data collection
- Local-only processing

### Architecture
- SwiftUI for declarative UI
- Combine for reactive state management
- MVVM pattern with centralized AppState
- Dependency Injection via ServiceContainer
- Protocol-driven service design
- Swift concurrency with @MainActor isolation

## User Flows

### Recording Flow
1. User launches app
2. Selects recording mode (fullscreen/window)
3. Configures camera/microphone options
4. Presses record (or global hotkey)
5. 3-second countdown
6. Recording starts
7. Press stop to end recording
8. Recording saved and appears in timeline

### Editing Flow
1. Open project with recorded clips
2. Arrange clips on timeline
3. Trim/split clips as needed
4. Add captions (manual or auto-generate)
5. Preview playback
6. Export final video

### Export Flow
1. Configure export settings (resolution, format)
2. Select destination
3. Start export
4. Monitor progress
5. Export completes with notification

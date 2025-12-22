# SaneVideo

SaneVideo is a macOS SwiftUI application designed for content creators to streamline video editing, recording, and AI-enhanced clipping workflows. It provides a modern, intuitive interface for importing, playing, recording, and automatically generating viral video clips using AI.

## Key Features

- **Video Import & Playback**: Drag-and-drop video player with support for importing local videos.
- **Camera & Microphone Recording**: Record new videos directly in the app with smart permission handling.
- **AI-Powered Auto-Clipping**: Uses Google's Gemini AI to detect and clip "viral moments" from videos automatically.
- **Speech-to-Text Captions**: Generates captions using speech recognition.
- **Magic Buttons Sidebar**: Quick-action buttons for common tasks like auto-clip, export, etc.
- **Toast Notifications**: Non-intrusive feedback for user actions and processing status.
- **Permission Management**: User-friendly UI in the sidebar to request and manage camera, microphone, and speech permissions without loops or annoying alerts.
- **Beautiful UI**: Gradient backgrounds, responsive layout with sidebar, central player, and top controls.

## Architecture

- **Monolithic ContentView.swift**: All components (models, services, views) consolidated into a single file for simplicity and easy setup.
- **Services**: `VideoService` for import/export/playback, `AIService` for Gemini integration.
- **Models**: `VideoProject`, `VideoClip`, `Caption`, etc.
- **Views**: `PlayerView`, `SidebarView`, `MagicButton`, `ToastView`.

## Setup & Build

Follow [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for complete setup, including adding privacy permissions to Info.plist.

1. Add camera, microphone, and speech recognition privacy descriptions.
2. Build with ⌘B and run with ⌘R.

## Design Philosophy

Focused on a seamless workflow for content creators:
- No complex timelines or editors – just import, AI-clip, export.
- "Magic" one-click actions.
- Handles permissions gracefully.
- Optimized for macOS with large window (1200x800 default).

## Dependencies

- SwiftUI (native macOS)
- AVFoundation (video handling)
- Speech framework (captions)
- Google Gemini API (AI clipping – API key required in code)

## Current State

The app is fully functional once permissions are set. Everything is self-contained in `ContentView.swift` (add via instructions if missing). Assets and app icon are pre-configured.

For full dev log and fixes, see [RESTART_HERE.md](RESTART_HERE.md).

🚀 **Ready for content creation!**
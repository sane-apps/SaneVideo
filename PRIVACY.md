# Privacy Policy

**Last updated: October 17, 2026**

SaneVideo is designed with privacy as a core principle. This document explains how the app handles your data.

## Our Philosophy

**Your projects stay local by default.** Recording, editing, and local export happen on your Mac unless you explicitly choose an external workflow.

## Data Collection

### What We DON'T Collect
- No crash reports sent externally
- No personal information
- No video content is uploaded by default

### What Stays Local
- **Video files** - Processed entirely on your device
- **Preferences** - Stored in macOS defaults system
- **Temporary files** - Cleaned up after processing

### Limited Network Uses
- **Updates** - Sparkle checks whether a newer app build exists
- **Licensing** - A license from an older paid version may be checked when you activate it
- **Aggregate app counts** - SaneApps may receive privacy-safe aggregate counts that are not project content
- **Speech model download** - The first time you make captions or run Clean Up, SaneVideo downloads the Parakeet speech model (about 600 MB) from Hugging Face once. Your audio never leaves your Mac; the model runs locally. Apple's on-device engine (Settings > Privacy) needs no download.

## Permissions Used

### File System Access
- **App container** - Preferences and the speech model live in `~/Library/Containers/com.sanevideo.app`
- **User-selected files** - Only files you explicitly open
- **Movies** - To save projects, recordings, and exports (Movies/SaneVideo)

### Camera/Microphone/Screen Recording
- Only accessed when you explicitly record or enable camera/screen capture
- Never accessed in background
- No data transmitted
- Screen Recording is controlled by macOS System Settings and may require restarting SaneVideo after approval

## Third-Party Services

SaneVideo never sends your recordings, audio, or projects to any service. Sharing a file happens only when you use the macOS share sheet yourself.

## Auto-Updates

When enabled, SaneVideo checks for updates via Sparkle framework:
- Connects to `sanevideo.com/appcast.xml`
- Only checks for version information
- No personal data transmitted

## Your Rights

You have full control:
- See everything SaneVideo stores: the app container above and `~/Movies/SaneVideo`
- Turn off optional features
- Remove all of it with the steps below

## Complete Uninstall

To remove all SaneVideo data:
```bash
# Move application to Trash
trash /Applications/SaneVideo.app

# Remove preferences
defaults delete com.sanevideo.app

# Move app data and the speech model (about 600 MB) to Trash
trash ~/Library/Containers/com.sanevideo.app

# Your recordings, projects and exports (only if you no longer want them)
trash ~/Movies/SaneVideo
```

## Contact

Questions about privacy? Email [hi@saneapps.com](mailto:hi@saneapps.com). Do not put private video names, paths, or customer data in a public issue.

## Changes

Any changes to this policy will be documented in the CHANGELOG and noted in release notes.

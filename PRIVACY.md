# Privacy Policy

**Last updated: May 12, 2026**

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
- **Licensing** - License status may be checked when you activate or validate Pro
- **Aggregate app counts** - SaneApps may receive privacy-safe aggregate counts that are not project content
- **Optional integrations** - Third-party upload/API features only use the network when you configure and choose them

## Permissions Used

### File System Access
- **Application Support** - To store preferences
- **User-selected files** - Only files you explicitly open
- **Movies/Desktop** - To save projects, recordings, and default exports
- **iCloud Drive** - Only if you enable optional iCloud sync

### Camera/Microphone/Screen Recording
- Only accessed when you explicitly record or enable camera/screen capture
- Never accessed in background
- No data transmitted
- Screen Recording is controlled by macOS System Settings and may require restarting SaneVideo after approval

## Third-Party Services

SaneVideo does not send your project media to third-party services by default. Optional upload/API integrations are separate from normal local recording and editing and require your explicit setup.

## Auto-Updates

When enabled, SaneVideo checks for updates via Sparkle framework:
- Connects to `sanevideo.com/appcast.xml`
- Only checks for version information
- No personal data transmitted

## Your Rights

You have full control:
- View all stored data in Application Support folder
- Disable all optional features
- Uninstall completely with no traces

## Complete Uninstall

To remove all SaneVideo data:
```bash
# Move application to Trash
trash /Applications/SaneVideo.app

# Remove preferences
defaults delete com.sanevideo.app

# Move application data to Trash
trash ~/Library/Application\ Support/SaneVideo
trash ~/Library/Caches/com.sanevideo.app
```

## Contact

Questions about privacy? Email [hi@saneapps.com](mailto:hi@saneapps.com). Do not put private video names, paths, or customer data in a public issue.

## Changes

Any changes to this policy will be documented in the CHANGELOG and noted in release notes.

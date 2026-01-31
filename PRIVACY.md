# Privacy Policy

**Last updated: January 19, 2026**

SaneVideo is designed with privacy as a core principle. This document explains how the app handles your data.

## Our Philosophy

**Your data stays on your device.** Period.

## Data Collection

### What We DON'T Collect
- No analytics or telemetry
- No crash reports sent externally
- No usage statistics
- No personal information
- No video content is ever uploaded

### What Stays Local
- **Video files** - Processed entirely on your device
- **Preferences** - Stored in macOS defaults system
- **Temporary files** - Cleaned up after processing

## Permissions Used

### File System Access
- **Application Support** - To store preferences
- **User-selected files** - Only files you explicitly open

### Camera/Microphone (if applicable)
- Only accessed when you explicitly record
- Never accessed in background
- No data transmitted

## Third-Party Services

SaneVideo uses no third-party services, SDKs, or analytics.

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
# Remove application
rm -rf /Applications/SaneVideo.app

# Remove preferences
defaults delete com.sanevideo.app

# Remove application data
rm -rf ~/Library/Application\ Support/SaneVideo
rm -rf ~/Library/Caches/com.sanevideo.app
```

## Contact

Questions about privacy? Open an issue on [GitHub](https://github.com/sane-apps/SaneVideo/issues).

## Changes

Any changes to this policy will be documented in the CHANGELOG and noted in release notes.

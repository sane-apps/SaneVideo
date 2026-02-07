# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

---

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **hi@saneapps.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

You should receive a response within 48 hours.

---

## Security Model

SaneVideo is a **video recording and editing application** that:

1. **Requires Camera, Microphone, and Screen Recording permissions**
2. **Stores projects locally** on your Mac
3. **Makes no analytics or telemetry requests** — no tracking, cloud sync, or data collection (Sparkle update checks are the only network activity, see PRIVACY.md)
4. **Uses Hardened Runtime** for macOS security compliance

### Data Handling

- All video/audio data stays on your device
- No user data is transmitted externally (Sparkle checks for updates only)
- Project files are stored in user-accessible locations

---

## Privacy

SaneVideo collects **zero** user data:

- No analytics
- No telemetry
- No crash reporting to external services
- No account required

See [README.md](README.md) for our full privacy details.

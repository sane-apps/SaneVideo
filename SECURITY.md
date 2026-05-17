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
3. **Keeps project media local by default** — network use is limited to updates, licensing, privacy-safe aggregate app counts, and optional integrations you configure (see PRIVACY.md)
4. **Uses Hardened Runtime** for macOS security compliance

### Data Handling

- All video/audio data stays on your device
- Project media is not uploaded by default
- Optional licensing, update, aggregate app-count, and integration requests do not include your project media
- Project files are stored in user-accessible locations

---

## Privacy

SaneVideo keeps project media local by default:

- No external crash reporting
- No project-media upload by default
- No account required for local recording, editing, or export
- Limited network requests may be used for updates, licensing, privacy-safe aggregate app counts, and optional integrations you configure

See [PRIVACY.md](PRIVACY.md) for the full privacy details.

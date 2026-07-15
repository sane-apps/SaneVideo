# SaneVideo Agent Instructions

Follow `~/AGENTS.md` first (cross-LLM policy source of truth). This file carries SaneVideo-specific facts.

Philosophy: `~/SaneApps/meta/Brand/NORTH_STAR.md`

## What Is This

Native macOS video recording and editing app. Local recording, editing, and export — no subscriptions.

## Source Of Truth

- Product behavior and setup: `README.md`
- Development workflow: `DEVELOPMENT.md`
- Architecture: `ARCHITECTURE.md`
- Current session context: `SESSION_HANDOFF.md`
- Project config: `project.yml` (XcodeGen)
- Feature status: [GitHub Issues](https://github.com/sane-apps/SaneVideo/issues)
- Swift services: `SaneVideo/Services/`; UI components: `SaneVideo/Views/`
- Code patterns: `.claude/rules/` directory
- Shared UI: `~/SaneApps/infra/SaneUI/`; hooks/tooling: `~/SaneApps/infra/SaneProcess/`

Product roster (canonical): macOS = SaneHosts, SaneClip, SaneClick, SaneSales, SaneVideo; iOS = SaneScan (iPhone/iPad only), SaneLot; SaaS = SaneCite. SaneBar is retired (free + OSS, never advertised as a peer product).

## Build & Test (Mini-first)

- Canonical route: run `ruby scripts/SaneMaster.rb verify` on the Mac Mini (build + unit tests). `scripts/SaneMaster.rb` is the main CLI (build, test, verify, gen_test, gen_mock, etc.); use it instead of raw `xcodebuild`.
- Local Xcode builds on the Air are an explicitly-approved fallback only.
- Release: `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project <path> --full` (ships ZIPs).
- Hooks are managed globally at `~/SaneApps/infra/SaneProcess/`; MCP health checks go through the shared `check-mcps` / `mcp_watchdog` tooling there.

## UI Readability Guardrail

- Do not ship gray-on-gray text.
- Do not use `.caption` or `.caption2` for normal body/supporting copy.
- Do not use hard-coded `.gray` or `Color.stone` for primary information.
- Prefer `Theme.Typography` and the `saneReadable*` modifiers for titles, labels, support text, and metadata.
- If a screen looks "subtle" at the cost of readability, it is wrong. Raise contrast and size first.

## Project Skills (`.claude/skills/`)

| Skill | Use for |
|-------|---------|
| `audio-timeline-sync` | Audio/video sync questions |
| `crash-analysis` | Crash log triage |
| `metal-performance` | GPU/Metal optimization |
| `swift-concurrency` | Async/await patterns |
| `swiftui-performance` | SwiftUI rendering performance |

## Research & Memory

- Past bugs/learnings: agentmemory `memory_recall` / `memory_smart_search` + Claude file memory. Serena is code-navigation only; its old memories are absorbed into agentmemory.
- Apple frameworks: `apple-docs` MCP. Library docs: `plugin:context7:context7` (resolve-library-id → query-docs). GitHub search: `gh` CLI.
- Verify APIs exist (`.swiftinterface`, apple-docs, type definitions) before coding against them; after 2 failures stop and research (see `~/AGENTS.md`).

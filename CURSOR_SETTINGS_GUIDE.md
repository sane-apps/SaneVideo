# Cursor Settings Guide

## Overview

This project includes optimized Cursor/VS Code settings for Swift/macOS development. All settings are configured based on project requirements in `DEVELOPMENT.md`.

## Settings Files

### `.vscode/settings.json`
Main editor settings including:
- Swift language configuration
- File size enforcement (500 line limit)
- SwiftLint integration
- File exclusions
- Editor behavior
- Performance optimizations

### `.vscode/extensions.json`
Recommended extensions for this project:
- Swift language support
- Git integration
- YAML support (for project.yml)
- Ruby support (for SaneMaster.rb)
- Markdown support (for documentation)

### `.vscode/tasks.json`
Pre-configured tasks for common operations:
- `SaneMaster: Verify` (default build task)
- `SaneMaster: Test Suite (Quick)`
- `SaneMaster: Test Suite (Full)`
- `SaneMaster: Doctor`
- `XcodeGen: Generate`
- `SwiftLint: Lint`
- `Validate Test References`
- `Check Deprecations`

### `.vscode/launch.json`
Debug configuration for running the app.

### `.cursor/settings.json`
Cursor-specific AI settings:
- Chat model configuration
- Code completion settings
- Project context inclusion
- Swift-specific optimizations

## Key Features

### 500 Line Limit Enforcement
- Ruler at 500 characters
- File size warnings
- Large file optimizations

### SwiftLint Integration
- Auto-fix on save
- Real-time linting
- Custom configuration support

### File Management
- Excludes build artifacts
- Watches only relevant files
- Proper file associations

### AI/Cursor Optimizations
- Includes DEVELOPMENT.md in context
- Excludes build artifacts from AI context
- Optimized for Swift code completion

## Usage

### Running Tasks
Press `Cmd+Shift+P` (or `Ctrl+Shift+P`) and type "Tasks: Run Task" to see all available tasks.

### Keyboard Shortcuts
- `Cmd+Shift+B` - Run default build task (SaneMaster: Verify)
- `F5` - Debug (after building)

### Extensions
When opening the project, Cursor will suggest installing recommended extensions.

## Customization

All settings can be customized. However, the following should remain:
- 500 line limit enforcement
- SwiftLint integration
- File exclusions (build artifacts)
- DEVELOPMENT.md in AI context

## Related Documentation

- `DEVELOPMENT.md` - Main SOP with all project rules
- `.cursorrules` - Cursor-specific rules
- `lefthook.yml` - Git hooks configuration


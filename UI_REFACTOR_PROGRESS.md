# UI Refactoring Progress

**Started**: 2025-12-22
**Status**: In Progress

## Completed Tasks

### 1. Created Reusable Common Components
- [x] `Views/Components/Common/SheetHeader.swift` - Standard header + footer for modal sheets
- [x] `Views/Components/Common/LabeledSliderControl.swift` - Slider with label, value, range hints
- [x] `Views/Components/Common/OptionButtonGroup.swift` - Horizontal preset buttons (FPS, width, speed)
- [x] `Views/Components/Common/InformationBox.swift` - Styled result/status display boxes

### 2. Split CaptionsSection (305 → 239 lines)
- [x] Extracted `ClipInfoSection.swift` - Clip metadata display
- [x] Extracted `CursorEnhancementsView.swift` - Cursor highlight toggle
- [x] Extracted `CaptionStylePreview.swift` - Caption style thumbnail
- [x] Refactored main `CaptionsSection.swift` to use new components

### 3. Verification
- [x] `xcodegen generate` - Project regenerated
- [x] `./Scripts/SaneMaster.rb verify` - 167 tests pass

---

## In Progress

### 4. Update Sheets to Use New Components
- [ ] `GIFExportSheet.swift` - Use SheetHeader, SheetFooter, IntOptionButtonGroup
- [ ] `TranscriptExportSheet.swift` - Use SheetHeader, SheetFooter
- [ ] `VoiceoverSettingsSheet.swift` - Use SheetHeader, SheetFooter, LabeledSliderControl
- [ ] `ThumbnailPickerSheet.swift` - Use SheetHeader, SheetFooter

### 5. Extract SidebarView Nested Components
- [ ] Extract `SidebarRailItem.swift`
- [ ] Extract `LibraryView.swift`
- [ ] Extract `LibraryClipRow.swift`
- [ ] Refactor `SidebarView.swift`

### 6. Fix VideoSection Rotation Logic
- [ ] Add `rotateToAngle(_:)` method to ProjectState
- [ ] Remove triple-click DispatchQueue hack from VideoSection

---

## Pending

### 7. Additional Cleanup (Optional)
- [ ] Update `VideoSection.swift` to use `DoubleOptionButtonGroup` for speed presets
- [ ] Update `AudioSection.swift` to use `LabeledSliderControl` for volume
- [ ] Update `BackgroundEffectsView.swift` to use new components
- [ ] Standardize all section headers to use `SubsectionHeader`

---

## How to Resume

1. Read this file for current status
2. Run `./Scripts/SaneMaster.rb verify` to confirm build is clean
3. Continue with next unchecked item
4. After changes: `xcodegen generate && ./Scripts/SaneMaster.rb verify`
5. Update this file as you complete tasks

---

## Files Changed

```
SaneVideo/Views/Components/
├── Common/                          (NEW DIRECTORY)
│   ├── SheetHeader.swift           (NEW)
│   ├── LabeledSliderControl.swift  (NEW)
│   ├── OptionButtonGroup.swift     (NEW)
│   └── InformationBox.swift        (NEW)
├── CaptionsSection.swift           (REFACTORED - 305→239 lines)
├── CaptionStylePreview.swift       (NEW - extracted)
├── ClipInfoSection.swift           (NEW - extracted)
└── CursorEnhancementsView.swift    (NEW - extracted)
```

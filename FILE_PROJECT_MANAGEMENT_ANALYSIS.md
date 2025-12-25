# File & Project Management Analysis
## Piece 2: Save/Load/File Handling
**Date**: 2025-12-24

---

## 🎯 Scope: File & Project Management

This analysis focuses on:
- Project saving/loading
- File bookmark management
- Security-scoped resources
- Missing file handling
- Concurrent operations
- Data corruption prevention

---

## 🔴 CRITICAL VULNERABILITIES IDENTIFIED

### 1. **Save Failure After State Update** ⚠️ CRITICAL

**Location**: `ProjectState.swift:189-219`, `ProjectState+ClipAddition.swift:170`

**Attack Vector**: 
```
1. User adds clip
2. currentProject updated
3. saveProject() called (async, debounced)
4. Save FAILS (disk full, permission, etc.)
5. State: currentProject has clip but file doesn't → data loss on app restart
```

**Current Code**:
```swift
currentProject = project  // ⚠️ State updated
saveProject(project)      // ⚠️ Async, might fail silently
```

**Impact**: 
- User sees clip in UI
- Project file doesn't have it
- Data loss on restart
- No indication save failed

**Fix Needed**: 
- Wait for save to complete before updating state (or rollback on failure)
- Show error if save fails
- Retry mechanism for transient failures

---

### 2. **Concurrent Save Race Condition** ⚠️ HIGH

**Location**: `ProjectState.swift:189-219`

**Attack Vector**: Rapid changes trigger multiple saves.

**Current Code**:
```swift
pendingSaveTask?.cancel()  // Cancels previous
pendingSaveTask = Task {
    // ... debounce ...
    try await projectStore.saveProject(project)
}
```

**Issue**: 
- If save is in progress and new save cancels it, old save might complete after new one
- Last-write-wins could lose intermediate changes
- No guarantee of save order

**Fix Needed**: 
- Queue saves instead of cancelling
- Or ensure only latest save proceeds
- Verify save order

---

### 3. **Atomic Write Not Guaranteed on Failure** ⚠️ HIGH

**Location**: `ProjectStore.swift:136-153`

**Attack Vector**: Atomic write might fail partially.

**Current Code**:
```swift
try data.write(to: fileURL, options: Data.WritingOptions.atomic)
```

**Issue**: 
- Atomic write creates temp file then moves it
- If move fails, temp file left behind
- If process crashes during move, file might be corrupted
- No verification that write succeeded

**Fix Needed**: 
- Verify file exists and is readable after write
- Clean up temp files on failure
- Add checksum verification

---

### 4. **Corrupted Project File Loading** ⚠️ MEDIUM

**Location**: `ProjectStore.swift:96-112`

**Attack Vector**: Corrupted JSON file causes load to fail silently.

**Current Code**:
```swift
for fileURL in projectFiles {
    do {
        let data = try Data(contentsOf: fileURL)
        let rawProject = try await MainActor.run {
            try JSONDecoder().decode(VideoProject.self, from: data)
        }
        projects.append(rawProject)
    } catch {
        AppLogger.project.error("Failed to load project...")
        // ⚠️ Silently skips corrupted file
    }
}
```

**Issue**: 
- Corrupted file is skipped silently
- User loses project with no warning
- No recovery mechanism
- No backup restoration

**Fix Needed**: 
- Show warning for corrupted files
- Attempt recovery (try loading partial data)
- Keep backup of last good save
- Offer to restore from backup

---

### 5. **Missing File Detection Race** ⚠️ MEDIUM

**Location**: `ProjectFileManager.swift:219-280`

**Attack Vector**: File exists check happens, then file deleted before use.

**Current Code**:
```swift
if !FileManager.default.fileExists(atPath: resolvedURL.path) {
    clip.isMissing = true
} else {
    clip.isMissing = false
}
// ⚠️ File might be deleted between check and use
```

**Issue**: 
- TOCTOU (Time-Of-Check-Time-Of-Use) race condition
- File might exist during check but be deleted before playback
- No re-check when actually accessing file

**Fix Needed**: 
- Check file existence when actually accessing
- Handle missing file errors gracefully
- Re-hydrate project if files go missing

---

### 6. **Bookmark Resolution Failure** ⚠️ MEDIUM

**Location**: `ProjectFileManager.swift:194-204, 219-280`

**Attack Vector**: Bookmark resolution fails, clip marked missing but no recovery.

**Current Code**:
```swift
do {
    let (resolvedURL, isStale) = try resolveBookmark(data: bookmarkData)
    // ...
} catch {
    AppLogger.project.warning("Failed to resolve bookmark...")
    clip.isMissing = true
    updatedClips.append(clip)  // ⚠️ Clip kept but unusable
}
```

**Issue**: 
- Bookmark fails → clip marked missing
- No way to recover (user can't re-select file)
- Project becomes partially broken
- No user notification

**Fix Needed**: 
- Show dialog asking user to locate missing file
- Update bookmark when user selects new location
- Or remove clip from project if can't resolve

---

### 7. **Security Scope Not Released on Error** ⚠️ MEDIUM

**Location**: `ProjectFileManager.swift:20-76`

**Attack Vector**: Error during loadClip releases scope, but what if error happens after?

**Current Code**:
```swift
let isAccessing = url.startAccessingSecurityScopedResource()
defer {
    if isAccessing {
        url.stopAccessingSecurityScopedResource()
    }
}
// ... might throw error ...
```

**Issue**: 
- Defer should handle this, but what if multiple scopes are active?
- SecurityScopeSession might not release all on error
- Resource leak if session not properly cleaned up

**Fix Needed**: 
- Ensure all scopes released in all error paths
- Add logging for scope leaks
- Use structured concurrency properly

---

### 8. **Duplicate Import Debounce Window** ⚠️ LOW

**Location**: `ProjectState+ClipAddition.swift:16-25`

**Attack Vector**: 2-second debounce might not catch rapid imports.

**Current Code**:
```swift
if let lastURL = lastImportedURL, let lastTime = lastImportTime,
   lastURL == url, now.timeIntervalSince(lastTime) < 2.0 {
    return  // Skip duplicate
}
```

**Issue**: 
- 2 seconds might be too short for some workflows
- Or too long for legitimate rapid imports
- What if same file imported from different sources?

**Fix Needed**: 
- Make debounce configurable
- Or check if clip already in project instead of time-based

---

### 9. **Optimization Failure Handling** ⚠️ MEDIUM

**Location**: `ProjectState+ClipAddition.swift:36-39, 101-130`

**Attack Vector**: Optimization fails, but import continues with original file.

**Current Code**:
```swift
if !nativeExtensions.contains(ext) {
    if let optimizedURL = await optimizeMedia(url: url) {
        targetURL = optimizedURL
    }
    // ⚠️ If optimization fails, uses original (might not work)
}
```

**Issue**: 
- If optimization fails, tries to use original
- Original might not be supported
- No fallback or user notification
- Import might fail later

**Fix Needed**: 
- Show error if optimization required but fails
- Or try original with better error message
- Don't silently fall back to unsupported format

---

### 10. **Load Projects Concurrent Access** ⚠️ LOW

**Location**: `ProjectStore.swift:64-134`

**Attack Vector**: Multiple calls to loadProjects() might create duplicate tasks.

**Current Code**:
```swift
let task = loadState.withLock { state -> Task<[VideoProject], Error> in
    if let existing = state {
        return existing  // ✅ Reuses existing
    }
    // Creates new task
}
```

**Issue**: 
- Lock prevents duplicates, but what if task completes between check and return?
- Race condition possible
- Multiple loads might happen if timing is wrong

**Fix Needed**: 
- Current implementation looks good, but verify
- Add logging to detect duplicate loads
- Ensure task is properly awaited

---

### 11. **Delete Project Doesn't Check for Active Use** ⚠️ MEDIUM

**Location**: `ProjectStore.swift:155-171`

**Attack Vector**: Delete project while it's currently open.

**Current Code**:
```swift
func deleteProject(_ project: VideoProject) async throws {
    // ...
    try fileManager.removeItem(at: fileURL)
    // ⚠️ No check if project is currentProject
}
```

**Issue**: 
- Can delete currently open project
- UI might still reference it
- Crashes or undefined behavior

**Fix Needed**: 
- Check if project is currentProject before delete
- Or close project first, then delete
- Prevent delete of active project

---

### 12. **Save Debounce Task Cancellation** ⚠️ MEDIUM

**Location**: `ProjectState.swift:192-218`

**Attack Vector**: Save task cancelled but save might have already started.

**Current Code**:
```swift
pendingSaveTask?.cancel()  // Cancels task
pendingSaveTask = Task {
    // New save task
}
```

**Issue**: 
- Cancelling task doesn't stop in-flight save
- Old save might complete after new one starts
- Last-write-wins could lose data

**Fix Needed**: 
- Wait for old save to complete before starting new one
- Or use a queue
- Verify save order

---

### 13. **No Backup Before Overwrite** ⚠️ HIGH

**Location**: `ProjectStore.swift:149`

**Attack Vector**: Save overwrites existing file, if save fails file is lost.

**Current Code**:
```swift
try data.write(to: fileURL, options: Data.WritingOptions.atomic)
// ⚠️ Overwrites existing file
```

**Issue**: 
- Atomic write should prevent this, but if it fails partially
- Old file might be corrupted
- No backup to restore from

**Fix Needed**: 
- Create backup before overwrite
- Restore backup if save fails
- Keep last N backups

---

### 14. **Hydration Doesn't Save Updated Bookmarks** ⚠️ MEDIUM

**Location**: `ProjectFileManager.swift:232-236`

**Attack Vector**: Stale bookmark updated but not saved to project file.

**Current Code**:
```swift
if isStale {
    if let newBookmark = try? createBookmark(for: resolvedURL) {
        clip.bookmarkData = newBookmark  // ⚠️ Updated in memory only
    }
}
// ⚠️ Updated project not saved
```

**Issue**: 
- Bookmark updated in memory
- Project file still has stale bookmark
- Next load will have same problem

**Fix Needed**: 
- Save project after hydration if bookmarks updated
- Or return flag indicating updates needed
- Persist updated bookmarks

---

### 15. **File Size Check Missing** ⚠️ LOW

**Location**: `ProjectFileManager.swift:173-180`

**Attack Vector**: Very large project files might cause memory issues.

**Current Code**:
```swift
func getFileSize(url: URL) -> Int64 {
    // Returns size but doesn't check limits
}
```

**Issue**: 
- No check for file size limits
- Very large files might cause OOM
- No warning for large projects

**Fix Needed**: 
- Check file size before loading
- Warn if project is very large
- Or stream-load large projects

---

## 🛡️ FIXES NEEDED (Priority Order)

### High Priority (Data Loss Prevention)

1. **Fix Save Failure After State Update**
   - Wait for save or rollback on failure
   - Show error to user
   - Retry mechanism

2. **Add Backup Before Overwrite**
   - Create backup before save
   - Restore on failure
   - Keep last N backups

3. **Fix Concurrent Save Race**
   - Queue saves or ensure order
   - Wait for previous save before new one
   - Verify save completion

### Medium Priority (Data Integrity)

4. **Fix Corrupted File Handling**
   - Show warning for corrupted files
   - Attempt recovery
   - Offer backup restoration

5. **Fix Missing File Detection Race**
   - Re-check when accessing file
   - Handle missing file errors
   - Re-hydrate on file loss

6. **Fix Bookmark Resolution Recovery**
   - Show dialog for missing files
   - Update bookmark when user locates file
   - Or remove clip if can't resolve

7. **Fix Hydration Bookmark Persistence**
   - Save project after bookmark updates
   - Persist updated bookmarks

8. **Fix Delete Active Project**
   - Check if project is currentProject
   - Prevent delete or close first

9. **Fix Optimization Failure**
   - Show error if optimization required
   - Don't silently fall back

### Low Priority (Polish)

10. **Improve Duplicate Import Detection**
    - Check if clip already in project
    - Make debounce configurable

11. **Add File Size Checks**
    - Warn for large projects
    - Check limits before load

12. **Improve Security Scope Management**
    - Ensure all scopes released
    - Add leak detection

---

## 📋 NEXT STEPS

1. Implement high-priority fixes
2. Test data loss scenarios
3. Move to next piece (Window Management)

---

**Status**: Analysis Complete - Ready for Fixes


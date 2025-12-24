# Test Video Assets Guide
## How to Add Real Videos for Testing
## Date: 2025-12-24

---

## 📁 Directory Structure

Test videos should be placed in:
```
SaneVideo/
  Tests/
    Assets/
      test_video.mp4          # Default test video (MP4, MOV, or M4V)
      test_video.mov          # MOV format also works
      test_video_short.mp4    # Short video for quick tests
      test_video_long.mov     # Long video (any supported format)
      test_video_with_audio.mp4  # Video with audio track
      test_video_silence.mov      # Video with silence segments (MOV format)
```

**Format Flexibility**: You can use `.mp4`, `.mov`, `.m4v`, or any other supported video format. The filename extension doesn't matter - just specify it in `TEST_ASSET_NAME` if different from default.

---

## 🔍 How TestEnvironment Finds Videos

The `TestEnvironment.mockAssetURL` property searches in this order:

1. **Environment Variable** (Best for CI/CD):
   ```bash
   PROJECT_DIR=/path/to/SaneVideo ./Scripts/SaneMaster.rb verify
   ```

2. **Current Directory** (Works if run from project root):
   ```bash
   cd /Users/sj/SaneVideo
   ./Scripts/SaneMaster.rb verify
   ```

3. **Hardcoded Dev Path** (Fallback):
   ```
   /Users/sj/SaneVideo/Tests/Assets/test_video.mp4
   ```

4. **Temporary Directory** (Last resort):
   ```
   /tmp/SaneVideo/test_video.mp4
   ```

---

## 📝 Recommended Test Videos

### Minimum Test Suite

1. **`test_video.mp4`** (Default)
   - **Duration**: 10-30 seconds
   - **Resolution**: 1920x1080 (or 1280x720)
   - **Content**: Simple scene with clear audio
   - **Purpose**: General feature testing

2. **`test_video_short.mp4`**
   - **Duration**: 3-5 seconds
   - **Purpose**: Quick tests, UI responsiveness

3. **`test_video_long.mp4`**
   - **Duration**: 2-5 minutes
   - **Purpose**: Stress tests, export tests, performance

4. **`test_video_with_audio.mp4`**
   - **Duration**: 15-30 seconds
   - **Audio**: Clear speech, music, or both
   - **Purpose**: Audio processing tests, Magic Fix

5. **`test_video_silence.mp4`**
   - **Duration**: 20-30 seconds
   - **Content**: Contains silence segments (3-5 seconds)
   - **Purpose**: Silence removal tests

---

## 🎬 Video Specifications

### Supported Formats

**Native Formats** (No conversion needed):
- ✅ **MP4** (`.mp4`) - Recommended, most compatible
- ✅ **MOV** (`.mov`) - QuickTime format, fully supported
- ✅ **M4V** (`.m4v`) - iTunes video format, fully supported

**Other Supported Formats** (Will be optimized/converted):
- ✅ **MPEG** (`.mpeg`, `.mpg`) - MPEG-1, MPEG-2
- ✅ **AVI** (`.avi`) - Windows format
- ✅ **Other video formats** - Any format AVFoundation can read

**Note**: Non-native formats will be automatically optimized to MP4/MOV during import.

### Recommended Format (For Best Performance)
- **Container**: MP4 or MOV
- **Video Codec**: H.264
- **Audio Codec**: AAC
- **Frame Rate**: 30fps or 60fps
- **Resolution**: 1920x1080 (Full HD) or 1280x720 (HD)

### Content Guidelines
- **Simple scenes**: Avoid complex motion for easier testing
- **Clear audio**: Speech or music that's easy to analyze
- **Good lighting**: Avoid extreme contrast or dark scenes
- **Stable camera**: Avoid shaky footage

---

## 📤 How to Add Videos

### Option 1: Manual Copy (Easiest)

1. Create the directory:
   ```bash
   mkdir -p /Users/sj/SaneVideo/Tests/Assets
   ```

2. Copy your video file:
   ```bash
   cp ~/Downloads/my_test_video.mp4 /Users/sj/SaneVideo/Tests/Assets/test_video.mp4
   ```

3. Verify it's found:
   ```bash
   ./Scripts/SaneMaster.rb verify
   # Check logs for: "Test asset found at: /Users/sj/SaneVideo/Tests/Assets/test_video.mp4"
   ```

### Option 2: Use SaneMaster.rb (If Available)

```bash
# If gen_assets command exists
./Scripts/SaneMaster.rb gen_assets
```

### Option 3: Generate Test Video (FFmpeg)

**Generate MP4**:
```bash
# Generate a simple test video (10 seconds, 1080p, MP4)
ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=1000:duration=10 \
       -c:v libx264 -preset fast -crf 23 \
       -c:a aac -b:a 192k \
       -pix_fmt yuv420p \
       /Users/sj/SaneVideo/Tests/Assets/test_video.mp4
```

**Generate MOV**:
```bash
# Generate a simple test video (10 seconds, 1080p, MOV)
ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=1000:duration=10 \
       -c:v libx264 -preset fast -crf 23 \
       -c:a aac -b:a 192k \
       -pix_fmt yuv420p \
       -f mov \
       /Users/sj/SaneVideo/Tests/Assets/test_video.mov
```

**Note**: Both formats work equally well. Use whichever is more convenient.

---

## ✅ Verification

### Check if Video is Found

```swift
// In a test
let testVideo = TestEnvironment.mockAssetURL
print("Test video path: \(testVideo.path)")
print("Exists: \(FileManager.default.fileExists(atPath: testVideo.path))")
```

### Run a Test That Uses Video

```bash
# Run a test that requires video
./Scripts/SaneMaster.rb verify --test SmartFeaturesComprehensiveTests
```

---

## 🚨 Important Notes

1. **Git Ignore**: Test videos are typically large and should be in `.gitignore`:
   ```
   Tests/Assets/*.mp4
   Tests/Assets/*.mov
   ```

2. **File Size**: Keep videos reasonable (< 100MB each)

3. **Naming**: Use descriptive names that indicate purpose:
   - `test_video.mp4` - Default
   - `test_video_short.mp4` - Short duration
   - `test_video_silence.mp4` - Contains silence

4. **Multiple Videos**: Use `TEST_ASSET_NAME` environment variable:
   ```bash
   # MP4 format
   TEST_ASSET_NAME=test_video_silence.mp4 ./Scripts/SaneMaster.rb verify
   
   # MOV format
   TEST_ASSET_NAME=test_video_silence.mov ./Scripts/SaneMaster.rb verify
   
   # M4V format
   TEST_ASSET_NAME=test_video_silence.m4v ./Scripts/SaneMaster.rb verify
   ```
   
   **Any supported format works** - just specify the full filename with extension.

---

## 📋 Checklist

- [ ] Create `Tests/Assets/` directory
- [ ] Add `test_video.mp4` (default)
- [ ] Add `test_video_short.mp4` (optional)
- [ ] Add `test_video_long.mp4` (optional)
- [ ] Add `test_video_with_audio.mp4` (optional)
- [ ] Add `test_video_silence.mp4` (optional)
- [ ] Verify videos are found by tests
- [ ] Add `Tests/Assets/*.mp4` to `.gitignore`

---

## 🔧 Troubleshooting

### Video Not Found

1. Check path:
   ```bash
   ls -la /Users/sj/SaneVideo/Tests/Assets/
   ```

2. Check TestEnvironment:
   ```swift
   print(TestEnvironment.mockAssetURL.path)
   ```

3. Use environment variable:
   ```bash
   PROJECT_DIR=/Users/sj/SaneVideo ./Scripts/SaneMaster.rb verify
   ```

### Test Fails with Video

1. Check video format:
   - ✅ MP4, MOV, M4V work natively
   - ✅ Other formats will be converted automatically
   - ❌ Corrupted files will fail
2. Check file permissions (should be readable)
3. Check file size (not corrupted or empty)
4. Verify format is readable by AVFoundation:
   ```bash
   # Quick check if video is valid
   ffprobe /Users/sj/SaneVideo/Tests/Assets/test_video.mov
   ```

---

**Recommendation**: 
- Start with one good test video (`.mp4`, `.mov`, or `.m4v` - your choice!)
- Add more as needed for specific test scenarios
- **Format doesn't matter** - use whatever is convenient (MP4, MOV, M4V all work equally well)


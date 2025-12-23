# 🍎 On-Device Architecture - SaneVideo

## ✅ **100% On-Device Processing**

SaneVideo uses **exclusively Apple's on-device APIs** for all Magic Fix operations. No cloud dependencies!

### Core On-Device Services

#### 1. **Speech Recognition** 🎤
- **API**: `SpeechAnalyzer` (macOS 26+)
- **Service**: `AppleSpeechService`
- **Features**: Real-time transcription, word-level timestamps
- **Performance**: Runs on Neural Engine (ANE)

#### 2. **Filler Word Detection** 🗣️
- **API**: `NaturalLanguage` framework (`NLTagger`)
- **Service**: `SmartFillerDetector`
- **Features**: Linguistic analysis, part-of-speech tagging
- **Performance**: On-device NLP models

#### 3. **Silence Detection** 🔇
- **API**: `Accelerate` framework (`vDSP`)
- **Service**: `SilenceDetector`
- **Features**: Real-time audio analysis, RMS calculation
- **Performance**: M1-optimized SIMD operations

#### 4. **Vision Analysis** 👁️
- **API**: `Vision` framework
- **Service**: `VisionOrchestrator`
- **Features**: 
  - Text recognition (`VNRecognizeTextRequest`)
  - Face detection (`VNDetectFaceRectanglesRequest`)
  - Saliency detection (`VNGenerateAttentionBasedSaliencyImageRequest`)
- **Performance**: Runs on Neural Engine (ANE)

#### 5. **Audio Enhancement** 🎙️
- **API**: `AVAudioEngine`, `AUSoundIsolation`
- **Service**: `SaneAudioEnhancementService`
- **Features**: EQ, voice isolation, dynamics processing
- **Performance**: Real-time audio processing

#### 6. **Video Rendering** 🎬
- **API**: `CoreImage` with Metal
- **Service**: `RenderingService`
- **Features**: GPU-accelerated effects, thermal-aware rendering
- **Performance**: Metal-backed CIContext

### Optional Cloud Services (Not Required)

Cloud APIs are **optional** and only used for:
- Title/description generation (if API keys are provided)
- Advanced caption refinement (if enabled)

**Default**: `.appleFoundation` (on-device when available)

### Privacy & Performance Benefits

✅ **100% Private** - All processing happens on-device  
✅ **No Internet Required** - Works offline  
✅ **Fast** - Neural Engine acceleration  
✅ **Free** - No API costs  
✅ **Secure** - No data leaves your device  

### Architecture Flow

```
Magic Fix Request
    ↓
1. Audio Enhancement (AVAudioEngine) ← On-Device
    ↓
2. Speech Transcription (SpeechAnalyzer) ← On-Device
    ↓
3. Filler Detection (NaturalLanguage) ← On-Device
    ↓
4. Silence Detection (Accelerate/vDSP) ← On-Device
    ↓
5. Vision Analysis (Vision Framework) ← On-Device
    ↓
6. Apply Cuts & Effects ← On-Device
    ↓
Complete! ✨
```

**No cloud calls in the core Magic Fix pipeline!**


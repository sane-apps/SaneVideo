# Metal Performance Optimization

> When to use: Working with real-time video filters, GPU rendering, or fixing frame drops/stuttering

---

## What This Is (Plain English)

Metal is Apple's GPU API for high-performance graphics. In SaneVideo, we use it for:

- **Real-time filters** at 120fps (Natural, Cinematic, Vintage)
- **Video compositing** during playback and export
- **Thumbnail generation** in background threads

The goal: GPU does the heavy lifting, CPU stays free for UI responsiveness.

---

## Key Concepts

### Metal Command Queue Pattern

All GPU work goes through command buffers:

```swift
// Create once, reuse forever
let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!

// Per-frame work
func renderFrame(_ texture: MTLTexture) {
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

    encoder.setComputePipelineState(filterPipeline)
    encoder.setTexture(texture, index: 0)
    encoder.setTexture(outputTexture, index: 1)

    let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadgroups = MTLSize(
        width: (texture.width + 15) / 16,
        height: (texture.height + 15) / 16,
        depth: 1
    )
    encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
    encoder.endEncoding()

    commandBuffer.commit()
}
```

### Triple Buffering for 120fps

Never wait for GPU - rotate through 3 buffers:

```swift
class TripleBuffer<T> {
    private var buffers: [T]
    private var index = 0
    private let semaphore = DispatchSemaphore(value: 3)

    func next() -> T {
        semaphore.wait()
        let buffer = buffers[index]
        index = (index + 1) % 3
        return buffer
    }

    func release() {
        semaphore.signal()
    }
}

// Usage
let texturePool = TripleBuffer(buffers: [texture1, texture2, texture3])

func render() {
    let texture = texturePool.next()
    commandBuffer.addCompletedHandler { _ in
        texturePool.release()
    }
}
```

### Compute vs Render Pipeline

| Pipeline | Use Case | Threadgroup Size |
|----------|----------|------------------|
| **Compute** | Filters, transforms, analysis | 16x16 or 8x8 |
| **Render** | Drawing to screen, compositing | N/A (uses vertices) |

For video filters, compute is almost always faster.

---

## SaneVideo Filter Architecture

### Filter Pipeline (RenderingService.swift)

```swift
actor RenderingService {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var filterPipelines: [FilterType: MTLComputePipelineState] = [:]

    func applyFilter(_ type: FilterType, to frame: CVPixelBuffer) async -> CVPixelBuffer {
        // Convert CVPixelBuffer to MTLTexture (zero-copy when possible)
        let inputTexture = makeTexture(from: frame)
        let outputTexture = makeOutputTexture(matching: inputTexture)

        guard let pipeline = filterPipelines[type],
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return frame  // Fallback to original
        }

        // Encode filter kernel
        encodeFilter(pipeline, input: inputTexture, output: outputTexture, in: commandBuffer)

        // Wait for completion (async-friendly)
        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            commandBuffer.commit()
        }

        return makePixelBuffer(from: outputTexture)
    }
}
```

### Shader Example (Filters.metal)

```metal
#include <metal_stdlib>
using namespace metal;

kernel void cinematicFilter(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) return;

    float4 color = input.read(gid);

    // Lift shadows, crush highlights (cinematic look)
    float3 rgb = color.rgb;
    rgb = pow(rgb, float3(0.9));           // Gamma lift
    rgb = mix(rgb, float3(0.5), 0.05);     // Reduce contrast slightly
    rgb.b *= 1.05;                          // Slight blue push

    output.write(float4(rgb, color.a), gid);
}
```

---

## Performance Patterns

### 1. Avoid CPU-GPU Sync Points

```swift
// ❌ BAD - waits for GPU every frame
commandBuffer.commit()
commandBuffer.waitUntilCompleted()  // BLOCKS!
let result = outputTexture

// ✅ GOOD - async completion
commandBuffer.addCompletedHandler { [weak self] _ in
    Task { @MainActor in
        self?.displayTexture(outputTexture)
    }
}
commandBuffer.commit()
```

### 2. Texture Format Selection

| Format | Use Case | Memory |
|--------|----------|--------|
| `.bgra8Unorm` | Display, UI | 4 bytes/pixel |
| `.rgba16Float` | HDR processing | 8 bytes/pixel |
| `.r8Unorm` | Masks, alpha | 1 byte/pixel |

```swift
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm,  // Match CVPixelBuffer format
    width: width,
    height: height,
    mipmapped: false
)
descriptor.usage = [.shaderRead, .shaderWrite]
descriptor.storageMode = .private  // GPU-only = fastest
```

### 3. CVPixelBuffer to MTLTexture (Zero-Copy)

```swift
func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
    var textureRef: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
        nil,
        textureCache,
        pixelBuffer,
        nil,
        .bgra8Unorm,
        CVPixelBufferGetWidth(pixelBuffer),
        CVPixelBufferGetHeight(pixelBuffer),
        0,
        &textureRef
    )
    guard status == kCVReturnSuccess, let textureRef else { return nil }
    return CVMetalTextureGetTexture(textureRef)
}
```

---

## Debugging GPU Issues

### Metal System Trace (Instruments)

```bash
# Profile GPU performance
xcrun xctrace record --template 'Metal System Trace' \
  --launch -- /path/to/SaneVideo.app
```

### GPU Frame Capture (Xcode)

1. Run app in Xcode
2. Click "GPU Frame Capture" button in debug bar
3. Inspect command buffer timeline
4. Look for:
   - Long encoder durations (shader too complex)
   - Sync points (CPU waiting for GPU)
   - Memory spikes (texture leaks)

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Frame drops at 4K | Texture too large | Use `.private` storage, tile rendering |
| Memory grows | Texture leak | Use autorelease pools, check retain cycles |
| Stuttering | CPU-GPU sync | Use triple buffering, async completion |
| Wrong colors | Format mismatch | Match CVPixelBuffer format exactly |

---

## Apple Silicon Optimizations

### Unified Memory Advantage

Apple Silicon shares memory between CPU and GPU - no copy needed:

```swift
// On Apple Silicon, .shared is free
descriptor.storageMode = .shared

// Access from both CPU and GPU
let contents = texture.buffer?.contents()
```

### Tile-Based Deferred Rendering

Apple GPUs render in 32x32 tiles. Optimize for this:

```swift
// Use 32x32 threadgroups when possible
let threadgroupSize = MTLSize(width: 32, height: 32, depth: 1)
```

---

## Verification

```bash
# Check for Metal warnings
log show --predicate 'subsystem == "com.apple.Metal"' --last 5m

# Profile frame time
xcrun metal-profiler capture --time 5 --output profile.gputrace

# Validate shaders at build time
xcrun metal -c Filters.metal -o Filters.air
xcrun metallib Filters.air -o default.metallib
```

---

*~200 lines • Last updated: 2026-01-15*

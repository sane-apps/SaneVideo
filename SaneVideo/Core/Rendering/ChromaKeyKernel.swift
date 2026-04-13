//
//  ChromaKeyKernel.swift
//  SaneVideo
//
//  Shared GPU-accelerated chroma key kernel for green screen removal.
//  Consolidates duplicate implementations for consistent behavior.
//

@preconcurrency import CoreImage

/// Shared chroma key kernel for green/blue screen removal.
/// Uses GPU-accelerated CIColorKernel for real-time performance.
enum ChromaKeyKernel {
    /// The GPU-accelerated chroma key kernel.
    /// Removes pixels matching the target color, preserving original alpha.
    ///
    /// - Parameters:
    ///   - s: Source pixel sample
    ///   - targetColor: RGB color to key out (e.g., green = [0, 1, 0])
    ///   - threshold: Sensitivity (0.0-1.0, lower = more selective)
    ///
    /// - Returns: Pixel with alpha set to 0 if close to target color
    static let kernel: CIColorKernel? = {
        CIColorKernel(source: """
            kernel vec4 chromaKey(sample_t s, float3 targetColor, float threshold) {
                // Calculate color distance using Euclidean distance
                float3 diff = s.rgb - targetColor;
                float dist = length(diff);

                // Create sharp mask: 0 if within threshold, 1 otherwise
                float alpha = dist < threshold ? 0.0 : 1.0;

                // Preserve original alpha channel for proper compositing
                return vec4(s.rgb, s.a * alpha);
            }
            """)
    }()

    /// Apply chroma key effect to an image.
    /// - Parameters:
    ///   - image: Source CIImage
    ///   - targetColor: RGB color to remove (each component 0.0-1.0)
    ///   - threshold: Sensitivity (0.0-1.0)
    /// - Returns: Keyed image with transparent background, or original if kernel unavailable
    static func apply(
        to image: CIImage,
        targetColor: SIMD3<Float>,
        threshold: Float
    ) -> CIImage {
        guard let kernel = kernel else {
            AppLogger.general.warning("ChromaKeyKernel: CIColorKernel not available")
            return image
        }

        let colorVector = CIVector(x: CGFloat(targetColor.x), y: CGFloat(targetColor.y), z: CGFloat(targetColor.z))

        return kernel.apply(
            extent: image.extent,
            arguments: [image, colorVector, threshold]
        ) ?? image
    }
}

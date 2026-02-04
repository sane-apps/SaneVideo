//
//  VideoEffect.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//  Phase 3: Video effects using CIFilter
//

import CoreImage
import Foundation

/// Effect categories for organized display
enum EffectCategory: String, CaseIterable {
  case magic
  case looks
  case adjustments
  case stylize
  case blur

  var displayName: String {
    switch self {
    case .magic: return String(localized: "effect.category.magic", defaultValue: "✨ Auto")
    case .looks: return String(localized: "effect.category.looks", defaultValue: "Looks")
    case .adjustments:
      return String(localized: "effect.category.adjustments", defaultValue: "Adjust")
    case .stylize: return String(localized: "effect.category.stylize", defaultValue: "Stylize")
    case .blur: return String(localized: "effect.category.blur", defaultValue: "Blur")
    }
  }
}

/// Types of video effects available - using Apple's CIFilter
enum VideoEffectType: String, Codable, CaseIterable, Identifiable {
  // Magic (AI-powered auto)
  case autoEnhance  // Apple's auto-adjustment
  case autoWhiteBalance  // Auto color correction

  // Looks (one-tap Apple photo effects)
  case noir
  case chrome
  case fade
  case instant
  case mono
  case tonal
  case sepia

  // Adjustments
  case brightness
  case contrast
  case saturation
  case exposure
  case vibrance
  case highlights
  case sharpen
  case warmth

  // Stylize
  case vignette
  case bloom
  case comic
  case pixellate
  case edges
  case crystallize
  case pointillize
  case hexagonalPixellate

  // Blur
  case blur
  case motionBlur
  case zoomBlur
  case bokeh
  case backgroundBlur  // AI-powered using Vision framework

  // Color Grading
  case colorInvert
  case posterize
  case falseColor
  case thermal
  case lut  // Professional LUT Support
  case chromaKey  // Green/Blue screen removal

  var id: String { rawValue }

  /// Category for grouping in UI
  nonisolated var category: EffectCategory {
    switch self {
    case .autoEnhance, .autoWhiteBalance:
      return .magic
    case .noir, .chrome, .fade, .instant, .mono, .tonal, .sepia, .colorInvert, .posterize,
      .falseColor, .thermal, .lut:
      return .looks
    case .brightness, .contrast, .saturation, .exposure, .vibrance, .highlights, .sharpen, .warmth:
      return .adjustments
    case .vignette, .bloom, .comic, .pixellate, .edges, .crystallize, .pointillize,
      .hexagonalPixellate:
      return .stylize
    case .blur, .motionBlur, .zoomBlur, .bokeh, .backgroundBlur, .chromaKey:
      return .blur
    }
  }

  /// Display name for UI
  nonisolated var displayName: String {
    switch self {
    case .autoEnhance: return String(localized: "effect.type.enhance", defaultValue: "Enhance")
    case .autoWhiteBalance:
      return String(localized: "effect.type.color_fix", defaultValue: "Color Fix")
    case .brightness: return String(localized: "effect.type.brightness", defaultValue: "Bright")
    case .contrast: return String(localized: "effect.type.contrast", defaultValue: "Contrast")
    case .saturation: return String(localized: "effect.type.saturation", defaultValue: "Saturate")
    case .vibrance: return String(localized: "effect.type.vibrance", defaultValue: "Vibrance")
    case .highlights: return String(localized: "effect.type.highlights", defaultValue: "Highlights")
    case .sharpen: return String(localized: "effect.type.sharpen", defaultValue: "Sharpen")
    case .warmth: return String(localized: "effect.type.warmth", defaultValue: "Warmth")
    case .noir: return String(localized: "effect.type.noir", defaultValue: "Noir")
    case .chrome: return String(localized: "effect.type.chrome", defaultValue: "Chrome")
    case .fade: return String(localized: "effect.type.fade", defaultValue: "Fade")
    case .instant: return String(localized: "effect.type.instant", defaultValue: "Instant")
    case .mono: return String(localized: "effect.type.mono", defaultValue: "Mono")
    case .tonal: return String(localized: "effect.type.tonal", defaultValue: "Tonal")
    case .sepia: return String(localized: "effect.type.sepia", defaultValue: "Sepia")
    case .exposure: return String(localized: "effect.type.exposure", defaultValue: "Exposure")
    case .colorInvert: return String(localized: "effect.type.invert", defaultValue: "Invert")
    case .falseColor:
      return String(localized: "effect.type.false_color", defaultValue: "False Color")
    case .thermal: return String(localized: "effect.type.thermal", defaultValue: "Heat Map")
    case .lut: return String(localized: "effect.type.lut", defaultValue: "Cinema Style")
    case .posterize: return String(localized: "effect.type.posterize", defaultValue: "Posterize")
    case .vignette: return String(localized: "effect.type.vignette", defaultValue: "Vignette")
    case .bloom: return String(localized: "effect.type.bloom", defaultValue: "Bloom")
    case .comic: return String(localized: "effect.type.comic", defaultValue: "Comic")
    case .pixellate: return String(localized: "effect.type.pixellate", defaultValue: "Pixellate")
    case .edges: return String(localized: "effect.type.edges", defaultValue: "Edges")
    case .crystallize:
      return String(localized: "effect.type.crystallize", defaultValue: "Crystallize")
    case .pointillize:
      return String(localized: "effect.type.pointillize", defaultValue: "Pointillize")
    case .hexagonalPixellate: return String(localized: "effect.type.mosaic", defaultValue: "Mosaic")
    case .blur: return String(localized: "effect.type.gaussian", defaultValue: "Gaussian")
    case .motionBlur: return String(localized: "effect.type.motion", defaultValue: "Motion")
    case .zoomBlur: return String(localized: "effect.type.zoom", defaultValue: "Zoom")
    case .bokeh: return String(localized: "effect.type.bokeh", defaultValue: "Bokeh")
    case .backgroundBlur:
      return String(localized: "effect.type.background", defaultValue: "Background")
    case .chromaKey: return String(localized: "effect.type.chroma_key", defaultValue: "Chroma Key")
    }
  }

  /// SF Symbol icon for the effect
  nonisolated var icon: String {
    switch self {
    case .autoEnhance: return "wand.and.stars"
    case .autoWhiteBalance: return "eyedropper.halffull"
    case .brightness: return "sun.max"
    case .contrast: return "circle.lefthalf.filled"
    case .saturation: return "paintpalette"
    case .exposure: return "camera.aperture"
    case .vibrance: return "sparkle"
    case .highlights: return "sun.and.horizon"
    case .sharpen: return "wand.and.rays"
    case .warmth: return "thermometer.sun"
    case .noir: return "camera.filters"
    case .chrome: return "circle.hexagongrid"
    case .fade: return "circle.dashed"
    case .instant: return "camera.viewfinder"
    case .mono: return "circle.fill"
    case .tonal: return "circle.bottomhalf.filled"
    case .sepia: return "photo.artframe"
    case .vignette: return "circle.inset.filled"
    case .bloom: return "sparkles"
    case .comic: return "bubble.left.and.bubble.right"
    case .pixellate: return "square.grid.3x3"
    case .edges: return "square.on.square.dashed"
    case .crystallize: return "diamond"
    case .pointillize: return "circle.grid.3x3"
    case .hexagonalPixellate: return "hexagon"
    case .blur: return "drop"
    case .motionBlur: return "arrow.right.circle"
    case .zoomBlur: return "arrow.up.left.and.arrow.down.right"
    case .bokeh: return "camera.aperture"
    case .backgroundBlur: return "person.crop.rectangle"
    case .chromaKey: return "circle.dashed.inset.filled"
    case .colorInvert: return "circle.lefthalf.striped.horizontal.inverse"
    case .posterize: return "squares.leading.rectangle"
    case .falseColor: return "theatermask.and.paintbrush"
    case .thermal: return "thermometer.variable"
    case .lut: return "cube.fill"
    }
  }

  /// CIFilter name for this effect type
  nonisolated var ciFilterName: String {
    switch self {
    case .autoEnhance: return "AutoAdjust"  // Special - uses CIImage.autoAdjustmentFilters()
    case .autoWhiteBalance: return "AutoWhiteBalance"  // Special handling
    case .brightness: return "CIColorControls"
    case .contrast: return "CIColorControls"
    case .saturation: return "CIColorControls"
    case .exposure: return "CIExposureAdjust"
    case .vibrance: return "CIVibrance"
    case .highlights: return "CIHighlightShadowAdjust"
    case .sharpen: return "CISharpenLuminance"
    case .warmth: return "CITemperatureAndTint"
    case .noir: return "CIPhotoEffectNoir"
    case .chrome: return "CIPhotoEffectChrome"
    case .fade: return "CIPhotoEffectFade"
    case .instant: return "CIPhotoEffectInstant"
    case .mono: return "CIPhotoEffectMono"
    case .tonal: return "CIPhotoEffectTonal"
    case .sepia: return "CISepiaTone"
    case .vignette: return "CIVignette"
    case .bloom: return "CIBloom"
    case .comic: return "CIComicEffect"
    case .pixellate: return "CIPixellate"
    case .edges: return "CIEdges"
    case .crystallize: return "CICrystallize"
    case .pointillize: return "CIPointillize"
    case .hexagonalPixellate: return "CIHexagonalPixellate"
    case .blur: return "CIGaussianBlur"
    case .motionBlur: return "CIMotionBlur"
    case .zoomBlur: return "CIZoomBlur"
    case .bokeh: return "CIBokehBlur"
    case .backgroundBlur: return "PersonSegmentation"  // Custom - uses Vision
    case .chromaKey: return "CIColorCube"
    case .colorInvert: return "CIColorInvert"
    case .posterize: return "CIColorPosterize"
    case .falseColor: return "CIFalseColor"
    case .thermal: return "CIThermal"
    case .lut: return "CIColorCube"
    }
  }

  /// Whether this effect is binary (on/off) vs adjustable
  nonisolated var isBinary: Bool {
    switch self {
    case .autoEnhance, .autoWhiteBalance, .noir, .chrome, .fade, .instant, .mono, .tonal, .comic,
      .edges, .colorInvert, .thermal:
      return true
    default:
      return false
    }
  }

  /// Default intensity for this effect
  nonisolated var defaultIntensity: Float {
    switch self {
    case .autoEnhance, .autoWhiteBalance: return 1.0
    case .brightness: return 0.0
    case .contrast: return 1.0
    case .saturation: return 1.0
    case .exposure: return 0.0
    case .vibrance: return 0.0
    case .highlights: return 0.0
    case .sharpen: return 0.0
    case .warmth: return 0.5
    case .noir, .chrome, .fade, .instant, .mono, .tonal: return 1.0
    case .sepia: return 0.8
    case .vignette: return 1.0
    case .bloom: return 0.5
    case .comic: return 1.0
    case .pixellate: return 8.0
    case .edges: return 1.0
    case .crystallize: return 20.0
    case .pointillize: return 10.0
    case .hexagonalPixellate: return 10.0
    case .blur: return 5.0
    case .motionBlur: return 10.0
    case .zoomBlur: return 5.0
    case .bokeh: return 10.0
    case .backgroundBlur: return 10.0
    case .chromaKey: return 0.2  // Default sensitivity
    case .colorInvert: return 1.0
    case .posterize: return 6.0
    case .falseColor: return 1.0
    case .thermal: return 1.0
    case .lut: return 1.0
    }
  }

  /// Intensity range for this effect
  nonisolated var intensityRange: ClosedRange<Float> {
    switch self {
    case .autoEnhance, .autoWhiteBalance: return 0.0...1.0
    case .brightness: return -0.5...0.5
    case .contrast: return 0.5...2.0
    case .saturation: return 0.0...2.0
    case .exposure: return -2.0...2.0
    case .vibrance: return -1.0...1.0
    case .highlights: return -1.0...1.0
    case .sharpen: return 0.0...2.0
    case .warmth: return 0.0...1.0
    case .noir, .chrome, .fade, .instant, .mono, .tonal, .comic, .edges: return 0.0...1.0
    case .sepia: return 0.0...1.0
    case .vignette: return 0.0...2.0
    case .bloom: return 0.0...1.0
    case .pixellate: return 1.0...50.0
    case .crystallize: return 1.0...100.0
    case .pointillize: return 1.0...50.0
    case .hexagonalPixellate: return 1.0...50.0
    case .blur: return 0.0...20.0
    case .motionBlur: return 0.0...50.0
    case .zoomBlur: return 0.0...20.0
    case .bokeh: return 0.0...30.0
    case .backgroundBlur: return 5.0...30.0
    case .chromaKey: return 0.0...1.0
    case .colorInvert: return 0.0...1.0
    case .posterize: return 2.0...20.0
    case .falseColor: return 0.0...1.0
    case .thermal: return 0.0...1.0
    case .lut: return 0.0...1.0
    }
  }
}

/// A video effect with configurable intensity
struct VideoEffect: Identifiable, Codable, Equatable, Sendable {
  var id: UUID = .init()
  var type: VideoEffectType
  var intensity: Float
  var color: String?  // Hex color, e.g. "#00FF00" for Green Screen

  // GPU-based Chroma Key Kernel - uses shared ChromaKeyKernel for consistency

  nonisolated init(type: VideoEffectType, intensity: Float? = nil, color: String? = nil) {
    self.type = type
    self.intensity = intensity ?? type.defaultIntensity
    self.color = color
  }

  /// Create a CIFilter configured for this effect
  /// nonisolated since VideoEffect is Sendable and this method only uses local data
  nonisolated func createFilter() -> CIFilter? {
    // Special effects handled differently or via Kernels
    switch type {
    case .autoEnhance, .autoWhiteBalance, .backgroundBlur, .chromaKey:
      return nil
    default:
      break
    }

    guard let filter = CIFilter(name: type.ciFilterName) else { return nil }

    switch type {
    case .brightness:
      filter.setValue(intensity, forKey: kCIInputBrightnessKey)
    case .contrast:
      filter.setValue(intensity, forKey: kCIInputContrastKey)
    case .saturation:
      filter.setValue(intensity, forKey: kCIInputSaturationKey)
    case .exposure:
      filter.setValue(intensity, forKey: kCIInputEVKey)
    case .vibrance:
      filter.setValue(intensity, forKey: "inputAmount")
    case .highlights:
      filter.setValue(intensity, forKey: "inputHighlightAmount")
    case .blur:
      filter.setValue(intensity, forKey: kCIInputRadiusKey)
    case .vignette:
      filter.setValue(intensity, forKey: kCIInputIntensityKey)
      filter.setValue(intensity * 2, forKey: kCIInputRadiusKey)
    case .sepia:
      filter.setValue(intensity, forKey: kCIInputIntensityKey)
    case .sharpen:
      filter.setValue(intensity, forKey: kCIInputSharpnessKey)
    case .warmth:
      // Warmth: 0 = cool (6500K), 0.5 = neutral, 1 = warm (3000K)
      let temperature = 6500 - (intensity * 3500)
      filter.setValue(CIVector(x: CGFloat(temperature), y: 0), forKey: "inputNeutral")
    case .bloom:
      filter.setValue(intensity * 10, forKey: kCIInputRadiusKey)
      filter.setValue(intensity, forKey: kCIInputIntensityKey)
    case .pixellate:
      filter.setValue(intensity, forKey: "inputScale")
    case .crystallize:
      filter.setValue(intensity, forKey: kCIInputRadiusKey)
    case .pointillize:
      filter.setValue(intensity, forKey: kCIInputRadiusKey)
    case .hexagonalPixellate:
      filter.setValue(intensity, forKey: "inputScale")
    case .motionBlur:
      filter.setValue(intensity, forKey: kCIInputRadiusKey)
      filter.setValue(0.0, forKey: kCIInputAngleKey)  // Horizontal motion
    case .zoomBlur:
      filter.setValue(intensity, forKey: "inputAmount")
    case .bokeh:
      filter.setValue(intensity, forKey: kCIInputRadiusKey)
      filter.setValue(1.0, forKey: "inputSoftness")
    case .posterize:
      filter.setValue(intensity, forKey: "inputLevels")
    case .falseColor:
      // Duo-tone effect: map shadows to blue, highlights to yellow
      filter.setValue(CIColor(red: 0.1, green: 0.1, blue: 0.5), forKey: "inputColor0")
      filter.setValue(CIColor(red: 1.0, green: 0.9, blue: 0.2), forKey: "inputColor1")
    case .lut:
      // Professional LUT Presets (Teal & Orange / Cinematic / Vintage)
      // For MVP, we use a calculated 3D color cube (dim=16) - Cached for performance
      let dimension = 16
      let data = LUTGenerator.cachedTealOrange
      filter.setValue(data, forKey: "inputCubeData")
      filter.setValue(dimension, forKey: "inputCubeDimension")
    case .noir, .chrome, .fade, .instant, .mono, .tonal, .comic, .edges, .colorInvert, .thermal:
      // Photo effects are binary - no intensity parameters needed
      break
    case .autoEnhance, .autoWhiteBalance, .backgroundBlur, .chromaKey:
      // Already handled above
      break
    }

    return filter
  }

  /// Apply effect to an image
  nonisolated func apply(to image: CIImage) -> CIImage? {
    // Handle Kernel-based effects
    if type == .chromaKey {
      let keyColor = color != nil ? CIColor(string: color!) : CIColor.green
      let targetColor = SIMD3(Float(keyColor.red), Float(keyColor.green), Float(keyColor.blue))
      return ChromaKeyKernel.apply(
        to: image,
        targetColor: targetColor,
        threshold: intensity
      )
    }

    // Handle Standard Filters
    guard let filter = createFilter() else { return nil }

    filter.setValue(image, forKey: kCIInputImageKey)
    return filter.outputImage
  }
}

// MARK: - Hashable

extension VideoEffect: Hashable {
  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(type)
    hasher.combine(intensity)
    hasher.combine(color)
  }
}

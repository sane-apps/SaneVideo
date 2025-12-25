//
//  VideoEffectGenerators.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreImage
import Foundation

// MARK: - LUT Generation

struct LUTGenerator {

  /// Cache the LUT data to prevent expensive CPU re-calculation every frame
  static let cachedTealOrange: Data = generateTealAndOrangeData(dimension: 16)

  /// Generates a Teal & Orange 3D LUT (Color Cube) data
  /// dimension: The cube size (e.g. 16, 32, 64)
  static func generateTealAndOrangeData(dimension: Int) -> Data {
    let size = dimension * dimension * dimension
    var data = Data(count: size * 4 * MemoryLayout<Float>.size)

    data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
      let floatPtr = ptr.bindMemory(to: Float.self)

      for z in 0..<dimension {
        for y in 0..<dimension {
          for x in 0..<dimension {
            let r = Float(x) / Float(dimension - 1)
            let g = Float(y) / Float(dimension - 1)
            let b = Float(z) / Float(dimension - 1)

            // Apply Teal & Orange transformation
            var newR = r
            var newG = g
            var newB = b

            // Simple "Teal & Orange" algorithm:
            if r > 0.5 {
              newR = min(1.0, r * 1.1)
              newG = g * 0.95
              newB = b * 0.8
            } else if b > 0.4 {
              newR = r * 0.8
              newG = min(1.0, g * 1.1)
              newB = min(1.0, b * 1.05)
            }

            // Contrast boost
            newR = pow(newR, 1.1)
            newG = pow(newG, 1.1)
            newB = pow(newB, 1.1)

            let offset = (z * dimension * dimension + y * dimension + x) * 4
            floatPtr[offset] = newR
            floatPtr[offset + 1] = newG
            floatPtr[offset + 2] = newB
            floatPtr[offset + 3] = 1.0  // Alpha
          }
        }
      }
    }

    return data
  }
}

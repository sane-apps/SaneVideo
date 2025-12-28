//
//  DebouncedSlider.swift
//  SaneVideo
//
//  Reusable slider that debounces value changes to prevent excessive updates.
//  Consolidates duplicate debounce logic from AudioSection and VideoSection.
//

import SwiftUI

/// A slider that debounces value changes before calling the update action.
/// Prevents excessive saves when user is dragging the slider.
struct DebouncedSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
  @Binding var value: V
  let range: ClosedRange<V>
  let step: V.Stride
  let debounceInterval: UInt64
  let onUpdate: (V) -> Void

  @State private var pendingUpdate: Task<Void, Never>?

  /// Creates a debounced slider.
  /// - Parameters:
  ///   - value: The current value binding (for immediate UI updates)
  ///   - range: The valid range for the slider
  ///   - step: The step increment
  ///   - debounceMs: Debounce interval in milliseconds (default 300ms)
  ///   - onUpdate: Called after debounce with the final value
  init(
    value: Binding<V>,
    in range: ClosedRange<V>,
    step: V.Stride = 0.01,
    debounceMs: Int = 300,
    onUpdate: @escaping (V) -> Void
  ) {
    self._value = value
    self.range = range
    self.step = step
    self.debounceInterval = UInt64(debounceMs) * 1_000_000
    self.onUpdate = onUpdate
  }

  var body: some View {
    Slider(value: $value, in: range, step: step)
      .onChange(of: value) { _, newValue in
        pendingUpdate?.cancel()
        pendingUpdate = Task {
          try? await Task.sleep(nanoseconds: debounceInterval)
          guard !Task.isCancelled else { return }
          await MainActor.run {
            onUpdate(newValue)
          }
        }
      }
  }
}

// MARK: - Preview

#if DEBUG
  #Preview {
    struct PreviewWrapper: View {
      @State private var value: Double = 0.5

      var body: some View {
        VStack {
          DebouncedSlider(value: $value, in: 0...1, step: 0.1) { newValue in
            print("Debounced update: \(newValue)")
          }
          Text("Value: \(value, specifier: "%.2f")")
        }
        .padding()
      }
    }
    return PreviewWrapper()
  }
#endif

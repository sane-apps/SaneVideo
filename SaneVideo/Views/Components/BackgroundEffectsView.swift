//
//  BackgroundEffectsView.swift
//  SaneVideo
//
//  Background effects using Apple Vision person segmentation
//  Blur, solid color, or image background replacement
//

import AppKit
import SwiftUI

struct BackgroundEffectsView: View {
  @Environment(AppState.self) var appState
  let clip: VideoClip
  @Binding var isOperationInProgress: Bool

  @State private var selectedEffect: BackgroundEffect?
  @State private var blurRadius: Float = 20
  @State private var selectedColor: Color = .green
  @State private var selectedImageURL: URL?
  @State private var isPickingImage = false

  init(clip: VideoClip, isOperationInProgress: Binding<Bool>) {
    self.clip = clip
    self._isOperationInProgress = isOperationInProgress
    _selectedEffect = State(initialValue: clip.backgroundEffect)
    if case .blur(let radius) = clip.backgroundEffect {
      _blurRadius = State(initialValue: radius)
    }
    if case .solidColor(let r, let g, let b, _) = clip.backgroundEffect {
      _selectedColor = State(initialValue: Color(red: r, green: g, blue: b))
    }
    if case .chromaKey(let r, let g, let b, _) = clip.backgroundEffect {
      _selectedColor = State(initialValue: Color(red: r, green: g, blue: b))
    }
    if case .image(let url) = clip.backgroundEffect {
      _selectedImageURL = State(initialValue: url)
    }
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // Header with toggle
      HStack {
        Label(
          String(localized: "background.header", defaultValue: "Background"),
          systemImage: "person.crop.rectangle"
        )
        .font(.caption.bold())

        Spacer()

        Toggle(
          "",
          isOn: Binding(
            get: { selectedEffect != nil },
            set: { enabled in
              if enabled {
                selectedEffect = .blur(radius: 20)
                saveEffect()
              } else {
                selectedEffect = nil
                saveEffect()
              }
            }
          )
        )
        .toggleStyle(.switch)
        .controlSize(.mini)
        .accessibilityIdentifier("background.toggle")
      }

      if selectedEffect != nil {
        // P1 FIX: 2x2 grid layout for effect type buttons
        VStack(spacing: 6) {
          HStack(spacing: 6) {
            EffectTypeButton(
              title: String(localized: "background.effect.blur", defaultValue: "Blur"),
              icon: "camera.filters",
              isSelected: isBlur,
              id: "background.effect.blur",
              action: {
                selectedEffect = .blur(radius: blurRadius)
                saveEffect()
              }
            )

            EffectTypeButton(
              title: String(localized: "background.effect.color", defaultValue: "Color"),
              icon: "paintpalette",
              isSelected: isSolidColor,
              id: "background.effect.color",
              action: {
                let components = selectedColor.cgColor?.components ?? [0, 1, 0, 1]
                selectedEffect = .solidColor(
                  red: CGFloat(components[0]),
                  green: CGFloat(components[1]),
                  blue: CGFloat(components[2]),
                  alpha: 1
                )
                saveEffect()
              }
            )
          }
          
          HStack(spacing: 6) {
            EffectTypeButton(
              title: String(localized: "background.effect.chroma", defaultValue: "Chroma"),
              icon: "circle.dashed.inset.filled",
              isSelected: isChromaKey,
              id: "background.effect.chroma",
              action: {
                // Default to green screen
                selectedEffect = .chromaKey(red: 0, green: 1, blue: 0, sensitivity: 0.2)
                selectedColor = .green
                saveEffect()
              }
            )

            EffectTypeButton(
              title: String(localized: "background.effect.image", defaultValue: "Image"),
              icon: "photo",
              isSelected: isImage,
              id: "background.effect.image",
              action: {
                isPickingImage = true
              }
            )
          }
        }

        // Effect-specific controls
        Group {
          if isBlur {
            blurControls
          } else if isSolidColor {
            solidColorControls
          } else if isChromaKey {
            chromaKeyControls
          } else if isImage {
            imageControls
          }
        }
        .padding(.vertical, 4)
      }
    }
    .fileImporter(
      isPresented: $isPickingImage,
      allowedContentTypes: [.image],
      allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result, let url = urls.first {
        selectedImageURL = url
        selectedEffect = .image(url: url)
        saveEffect()
      }
    }
    // CRITICAL FIX: Sync state when clip changes externally
    .onChange(of: clip.backgroundEffect) { _, newEffect in
      if selectedEffect != newEffect {
        selectedEffect = newEffect
        // Update related state
        if case .blur(let radius) = newEffect {
          blurRadius = radius
        }
        if case .solidColor(let r, let g, let b, _) = newEffect {
          selectedColor = Color(red: r, green: g, blue: b)
        }
        if case .chromaKey(let r, let g, let b, _) = newEffect {
          selectedColor = Color(red: r, green: g, blue: b)
        }
        if case .image(let url) = newEffect {
          selectedImageURL = url
        }
      }
    }
  }

  // MARK: - Helpers

  private var isBlur: Bool {
    if case .blur = selectedEffect { return true }
    return false
  }

  private var isSolidColor: Bool {
    if case .solidColor = selectedEffect { return true }
    return false
  }

  private var isImage: Bool {
    if case .image = selectedEffect { return true }
    return false
  }

  private var isChromaKey: Bool {
    if case .chromaKey = selectedEffect { return true }
    return false
  }

  private var chromaSensitivity: Float {
    if case .chromaKey(_, _, _, let sensitivity) = selectedEffect {
      return sensitivity
    }
    return 0.2
  }

  private func updateChromaKey(sensitivity: Float? = nil) {
    let components = selectedColor.cgColor?.components ?? [0, 1, 0, 1]
    let finalSensitivity = sensitivity ?? chromaSensitivity

    selectedEffect = .chromaKey(
      red: components[0],
      green: components[1],
      blue: components[2],
      sensitivity: finalSensitivity
    )
    saveEffect()
  }

  private var colorPresets: [(name: String, color: Color)] {
    [
      ("Green Screen", .green),
      ("Black", .black),
      ("White", .white),
      ("Blue", .blue),
      ("Gray", .gray)
    ]
  }

  // MARK: - Effect Subviews

  private var blurControls: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(localized: "background.blur.intensity", defaultValue: "Blur Intensity"))
        .font(.caption2)
        .foregroundColor(.secondary)

      HStack {
        Slider(value: $blurRadius, in: 5...50, step: 1)
          .accessibilityIdentifier("background.blur_slider")
          .onChange(of: blurRadius) { _, newValue in
            selectedEffect = .blur(radius: newValue)
            saveEffect()
          }

        Text("\(Int(blurRadius))")
          .font(.caption.monospacedDigit())
          .frame(width: 25)
      }

      // Presets
      HStack(spacing: 4) {
        ForEach(
          [
            (10, String(localized: "background.blur.light", defaultValue: "Light")),
            (20, String(localized: "background.blur.medium", defaultValue: "Medium")),
            (35, String(localized: "background.blur.heavy", defaultValue: "Heavy"))
          ], id: \.0
        ) { preset in
          Button(preset.1) {
            blurRadius = Float(preset.0)
            selectedEffect = .blur(radius: blurRadius)
            saveEffect()
          }
          .buttonStyle(.bordered)
          .controlSize(.mini)
          .tint(Int(blurRadius) == preset.0 ? .accentColor : nil)
          .accessibilityIdentifier("background.blur_preset.\(preset.0)")
        }
      }
    }
  }

  private var solidColorControls: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(localized: "background.color.label", defaultValue: "Background Color"))
        .font(.caption2)
        .foregroundColor(.secondary)

      ColorPicker("", selection: $selectedColor, supportsOpacity: false)
        .labelsHidden()
        .accessibilityIdentifier("background.color_picker")
        .onChange(of: selectedColor) { _, newColor in
          let components = newColor.cgColor?.components ?? [0, 1, 0, 1]
          selectedEffect = .solidColor(
            red: CGFloat(components[0]),
            green: CGFloat(components[1]),
            blue: CGFloat(components[2]),
            alpha: 1
          )
          saveEffect()
        }

      // Color presets
      HStack(spacing: 6) {
        ForEach(colorPresets, id: \.name) { preset in
          Circle()
            .fill(preset.color)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
            .onTapGesture {
              selectedColor = preset.color
              let components = preset.color.cgColor?.components ?? [0, 1, 0, 1]
              selectedEffect = .solidColor(
                red: CGFloat(components[0]),
                green: CGFloat(components[1]),
                blue: CGFloat(components[2]),
                alpha: 1
              )
              saveEffect()
            }
            .help(preset.name)
            .accessibilityIdentifier(
              "background.color_preset.\(preset.name.lowercased().replacingOccurrences(of: " ", with: "_"))"
            )
        }
      }
    }
  }

  private var chromaKeyControls: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(localized: "background.chroma.key_color", defaultValue: "Key Color"))
        .font(.caption2)
        .foregroundColor(.secondary)

      HStack {
        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
          .labelsHidden()
          .accessibilityIdentifier("background.chroma_color_picker")
          .onChange(of: selectedColor) { _, _ in
            updateChromaKey()
          }

        // Common key colors
        ForEach([Color.green, Color.blue, Color(red: 1, green: 0, blue: 1)], id: \.self) { color in
          Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .onTapGesture {
              selectedColor = color
              updateChromaKey()
            }
        }
      }

      Divider().padding(.vertical, 4)

      Text(String(localized: "background.chroma.sensitivity", defaultValue: "Sensitivity"))
        .font(.caption2)
        .foregroundColor(.secondary)

      HStack {
        Slider(
          value: Binding(
            get: { chromaSensitivity },
            set: { newValue in
              updateChromaKey(sensitivity: newValue)
            }
          ), in: 0.0...1.0
        )
        .accessibilityIdentifier("background.chroma_sensitivity_slider")

        Text(String(format: "%.2f", chromaSensitivity))
          .font(.caption.monospacedDigit())
          .frame(width: 35)
      }
    }
  }

  private var imageControls: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        String(localized: "background.image.virtual", defaultValue: "Virtual Background")
      )
      .font(.caption2)
      .foregroundColor(.secondary)

      if let url = selectedImageURL {
        HStack {
          AsyncImage(url: url) { image in
            image.resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            Rectangle().fill(Color.secondary.opacity(0.3))
          }
          .frame(width: 60, height: 34)
          .cornerRadius(4)

          Text(url.lastPathComponent)
            .font(.caption2)
            .lineLimit(1)

          Spacer()

          Button {
            isPickingImage = true
          } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
              .font(.caption)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("background.change_image")
        }
      } else {
        Button {
          isPickingImage = true
        } label: {
          Label(
            String(localized: "background.image.choose", defaultValue: "Choose Image"),
            systemImage: "photo.badge.plus"
          )
          .font(.caption)
          .frame(maxWidth: .infinity)
          .padding(8)
          .background(Color.secondary.opacity(0.15))
          .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("background.choose_image")
      }
    }
  }

  private func saveEffect() {
    appState.projectState.updateClipBackgroundEffect(clipId: clip.id, effect: selectedEffect)
  }
}

// MARK: - Effect Type Button

private struct EffectTypeButton: View {
  let title: String
  let icon: String
  let isSelected: Bool
  let id: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: icon)
          .font(.system(size: 16))
        Text(title)
          .font(.system(size: 9))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
      .foregroundColor(isSelected ? .accentColor : .secondary)
      .cornerRadius(6)
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }
}

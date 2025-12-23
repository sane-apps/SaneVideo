//
//  MainContentView+Export.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Menu Functions

extension MainContentView {
  /// Export as animated GIF using FFmpeg
  func exportAsGIF() {
    guard let project = appState.projectState.currentProject,
      let clip = project.timeline.tracks.first?.clips.first
    else {
      ServiceContainer.shared.toastManager.show(
        String(localized: "toast.error.no_clip_to_export", defaultValue: "No clip to export"),
        type: .error)
      return
    }

    ServiceContainer.shared.toastManager.show(
      String(localized: "toast.exporting_gif", defaultValue: "🎞️ Exporting GIF..."))

    Task {
      do {
        let outputURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("\(project.name)_clip.gif")

        try await ServiceContainer.shared.ffmpegService.exportAsGIF(
          inputURL: clip.url, outputURL: outputURL)

        // Show save panel
        await MainActor.run {
          let savePanel = NSSavePanel()
          savePanel.allowedContentTypes = [.gif]
          savePanel.nameFieldStringValue = "\(project.name).gif"

          savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
              try? FileManager.default.copyItem(at: outputURL, to: url)
              ServiceContainer.shared.toastManager.show(
                String(localized: "toast.gif_saved", defaultValue: "GIF saved!"))
            }
          }
        }
      } catch {
        await MainActor.run {
          ServiceContainer.shared.toastManager.show(
            String(localized: "toast.error.gif_failed", defaultValue: "GIF export failed")
              + ": \(error.localizedDescription)", type: .error)
        }
      }
    }
  }

  /// Export transcript as PDF
  func exportTranscriptPDF() {
    guard let project = appState.projectState.currentProject else {
      ServiceContainer.shared.toastManager.show(
        String(localized: "toast.error.no_project", defaultValue: "No project open"), type: .error)
      return
    }

    let captions = project.timeline.tracks
      .flatMap { $0.clips }
      .flatMap { $0.captions }

    guard !captions.isEmpty else {
      ServiceContainer.shared.toastManager.show(
        String(
          localized: "toast.error.no_captions_for_pdf",
          defaultValue: "No captions to export. Generate captions first."), type: .error)
      return
    }

    ServiceContainer.shared.toastManager.show(
      String(localized: "toast.generating_pdf", defaultValue: "📄 Generating PDF..."))

    Task {
      do {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
          .first!
        let outputURL = desktopURL.appendingPathComponent("\(project.name)_Transcript.pdf")

        try await ServiceContainer.shared.pdfService.generateStudyGuide(
          for: project, outputURL: outputURL)

        await MainActor.run {
          ServiceContainer.shared.toastManager.show(
            String(localized: "toast.pdf_saved", defaultValue: "PDF saved to Desktop!"))
          NSWorkspace.shared.open(outputURL)
        }
      } catch {
        await MainActor.run {
          ServiceContainer.shared.toastManager.show(
            String(localized: "toast.error.pdf_failed", defaultValue: "PDF export failed"),
            type: .error)
        }
      }
    }
  }

  /// Generate AI thumbnail
  func generateThumbnail() {
    guard let project = appState.projectState.currentProject,
      let clip = project.timeline.tracks.first?.clips.first
    else {
      ServiceContainer.shared.toastManager.show(
        String(
          localized: "toast.error.no_clip_for_thumbnail", defaultValue: "No clip for thumbnail"),
        type: .error)
      return
    }

    ServiceContainer.shared.toastManager.show(
      String(localized: "toast.generating_thumbnail", defaultValue: "🎨 Generating thumbnail..."))

    Task {
      do {
        let image = try await ServiceContainer.shared.thumbnailService.generateBestThumbnail(
          for: clip.url)
        await MainActor.run {
          // Copy to clipboard
          NSPasteboard.general.clearContents()
          NSPasteboard.general.writeObjects([image])
          ServiceContainer.shared.toastManager.show(
            String(
              localized: "toast.thumbnail_copied_clipboard",
              defaultValue: "✅ Thumbnail copied to clipboard!"))
        }
      } catch {
        await MainActor.run {
          ServiceContainer.shared.toastManager.show(
            String(
              localized: "toast.error.thumbnail_failed", defaultValue: "Thumbnail generation failed"
            ), type: .error)
        }
      }
    }
  }

  /// Generate voiceover from captions
  func generateVoiceover() {
    guard let project = appState.projectState.currentProject else {
      ServiceContainer.shared.toastManager.show("No project open", type: .error)
      return
    }

    let captions = project.timeline.tracks
      .flatMap { $0.clips }
      .flatMap { $0.captions }

    guard !captions.isEmpty else {
      ServiceContainer.shared.toastManager.show(
        String(
          localized: "toast.error.no_captions_for_voiceover",
          defaultValue: "No captions for voiceover. Generate captions first."), type: .error)
      return
    }

    ServiceContainer.shared.toastManager.show(
      String(localized: "toast.generating_voiceover", defaultValue: "🎤 Generating voiceover..."))

    Task {
      do {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
          .first!
        let outputURL = desktopURL.appendingPathComponent("\(project.name)_Voiceover.m4a")

        try await ServiceContainer.shared.voiceoverService.generateVoiceoverFromCaptions(
          captions, outputURL: outputURL)

        await MainActor.run {
          ServiceContainer.shared.toastManager.show(
            String(
              localized: "toast.voiceover_saved_desktop",
              defaultValue: "✅ Voiceover saved to Desktop!"))
          NSWorkspace.shared.open(outputURL)
        }
      } catch {
        await MainActor.run {
          ServiceContainer.shared.toastManager.show(
            String(localized: "toast.error.voiceover_failed", defaultValue: "Voiceover failed")
              + ": \(error.localizedDescription)", type: .error)
        }
      }
    }
  }
}

// MARK: - Overlay Helpers
extension MainContentView {
  @ViewBuilder
  func MagicOverlayView() -> some View {
    // Thermal Warning
    if ThermalManager.shared.isThermalPressureHigh {
      VStack {
        HStack {
          Image(systemName: "thermometer.sun.fill")
            .foregroundColor(.orange)
          Text(
            ThermalManager.shared.performanceLevel == .emergency
              ? String(
                localized: "thermal.emergency",
                defaultValue: "System Overheating: Performance reduced")
              : String(
                localized: "thermal.throttled", defaultValue: "System Hot: Optimizing performance")
          )
          .font(.caption)
          .fontWeight(.medium)
          Spacer()
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .padding()
        Spacer()
      }
      .transition(.move(edge: .top).combined(with: .opacity))
      .accessibilityIdentifier("thermal.status.overlay")
    }
  }
}

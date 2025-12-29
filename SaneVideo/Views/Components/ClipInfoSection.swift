//
//  ClipInfoSection.swift
//  SaneVideo
//
//  Displays basic clip metadata (name, duration, resolution)
//

import AVFoundation
import SwiftUI

/// Displays basic metadata about a video clip
struct ClipInfoSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    @State private var resolution: String = "Loading..."

    /// Display-friendly name for the clip
    private var displayName: String {
        let filename = clip.url.deletingPathExtension().lastPathComponent
        if UUID(uuidString: filename) != nil {
            let prefix = String(filename.prefix(8))
            return "Recording \(prefix)"
        }
        return filename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoRow(label: "Name", value: displayName)
            InfoRow(label: "Duration", value: String(format: "%.2fs", clip.duration.seconds))
            InfoRow(label: "Resolution", value: resolution)
            
            // P0 FIX: Show file path (truncated if long)
            if let filePath = filePathDisplay {
                InfoRow(label: "Location", value: filePath)
            }
            
            // P0 FIX: Show file size
            if let fileSize = fileSizeDisplay {
                InfoRow(label: "Size", value: fileSize)
            }
            
            // P0 FIX: Missing file recovery
            if clip.isMissing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("File Missing")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                    
                    Button {
                        locateMissingFile()
                    } label: {
                        Label("Locate File", systemImage: "magnifyingglass")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("clip_info.locate_file")
                    .accessibilityLabel("Locate missing file")
                    .accessibilityHint("Opens a file picker to locate the missing video file")
                    // REMOVED: .focusable() - was causing yellow focus ring
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .task(id: clip.url) {
            await loadResolution()
            await loadFileInfo()
        }
    }
    
    // P0 FIX: File path display (truncated)
    private var filePathDisplay: String? {
        let path = clip.url.path
        if path.count > 50 {
            let components = path.components(separatedBy: "/")
            if components.count > 3 {
                return ".../\(components.suffix(3).joined(separator: "/"))"
            }
        }
        return path
    }
    
    // P0 FIX: File size display
    @State private var fileSizeDisplay: String?
    
    private func loadFileInfo() async {
        guard !clip.isMissing else {
            fileSizeDisplay = "N/A"
            return
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: clip.url.path)
            if let size = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                await MainActor.run {
                    fileSizeDisplay = formatter.string(fromByteCount: size)
                }
            }
        } catch {
            await MainActor.run {
                fileSizeDisplay = "Unknown"
            }
        }
    }
    
    // P0 FIX: Locate missing file
    private func locateMissingFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Locate missing video file: \(displayName)"
        panel.prompt = "Relink"
        
        panel.begin { [clip] response in
            if response == .OK, let newURL = panel.url {
                // P0 FIX: Validate file exists and is readable
                guard FileManager.default.fileExists(atPath: newURL.path) else {
                    Task { @MainActor in
                        ServiceContainer.shared.toastManager.show(
                            "Selected file does not exist. Please choose a valid video file.",
                            type: .error
                        )
                    }
                    return
                }
                
                // P0 FIX: Update clip URL in ProjectState
                Task { @MainActor in
                    // Relink clip to new file location
                    appState.projectState.relinkClip(clip, to: newURL)
                    ServiceContainer.shared.toastManager.show(
                        "File relinked successfully",
                        type: .success
                    )
                }
            } else if response == .cancel {
                // User cancelled - no action needed
            }
        }
    }

    private func loadResolution() async {
        // CRITICAL FIX: Add timeout and error handling
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                // Timeout after 5 seconds
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if resolution == "Loading..." {
                        resolution = "Timeout"
                    }
                }
            }
            
            group.addTask {
                let asset = AVURLAsset(url: clip.url)
                // CRITICAL FIX: Check if file exists first
                guard FileManager.default.fileExists(atPath: clip.url.path) else {
                    await MainActor.run {
                        resolution = "File Missing"
                    }
                    return
                }
                
                if let track = try? await asset.loadTracks(withMediaType: .video).first {
                    if let size = try? await track.load(.naturalSize) {
                        await MainActor.run {
                            resolution = "\(Int(size.width)) × \(Int(size.height))"
                        }
                        return
                    }
                }
                await MainActor.run {
                    resolution = "Unknown"
                }
            }
        }
    }
}

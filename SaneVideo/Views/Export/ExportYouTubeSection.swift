//
//  ExportYouTubeSection.swift
//  SaneVideo
//
//  Extracted from ExportView.swift
//  Contains YouTube upload configuration
//

import SwiftUI

struct ExportYouTubeSection: View {
    var youtubeService: YouTubeService
    @Binding var showYouTubeUpload: Bool
    @Binding var videoTitle: String
    @Binding var videoDescription: String
    @Binding var isGeneratingAI: Bool
    let hasCaptions: Bool
    let onGenerateAI: () -> Void

    var body: some View {
        if showYouTubeUpload {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(String(localized: "export.youtube.header", defaultValue: "YouTube Details"), systemImage: "play.rectangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)

                        Spacer()

                        Button {
                            onGenerateAI()
                        } label: {
                            Group {
                                if isGeneratingAI {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(String(localized: "action.auto_generate", defaultValue: "Auto-Generate"), systemImage: "wand.and.stars")
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                LinearGradient(
                                    colors: [.teal, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .opacity(hasCaptions ? 0.8 : 0.4)
                            )
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasCaptions || isGeneratingAI)
                        .help(hasCaptions ? "Generate title & description from transcript" : "Requires captions - generate them first")
                    }

                    TextField(String(localized: "export.youtube.title", defaultValue: "Title"), text: $videoTitle)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("export.youtube.title_field")
                    TextField(String(localized: "export.youtube.description", defaultValue: "Description"), text: $videoDescription)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("export.youtube.description_field")

                    if youtubeService.isUploading {
                        ProgressView(String(localized: "export.youtube.uploading", defaultValue: "Uploading..."), value: youtubeService.uploadProgress, total: 1.0)
                    }
                }
                .padding(8)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

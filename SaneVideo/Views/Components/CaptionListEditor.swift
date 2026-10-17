import AVFoundation
import SwiftUI

struct CaptionListEditor: View {
    @Environment(AppState.self) var appState
    let project: VideoProject
    
    var body: some View {
        @Bindable var projectState = appState.projectState
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($projectState.currentProject.bound.timeline.tracks) { $track in
                        ForEach($track.clips) { $clip in
                            ForEach($clip.captions) { $caption in
                                CaptionRow(
                                    caption: $caption,
                                    clipStart: clip.startTime,
                                    isActive: isCaptionActive(caption, in: clip),
                                    style: project.captionStyle,
                                    onSeek: {
                                        // caption.startTime is asset time: timeline time = clip.startTime + (caption.startTime - clip.trimStart).
                                        
                                        let effectiveDuration = CMTimeSubtract(caption.startTime, clip.trimStart)
                                        let seekTime = CMTimeAdd(clip.startTime, effectiveDuration)
                                        appState.playbackState.seek(to: seekTime)
                                    },
                                    onDelete: {
                                        appState.projectState.deleteCaptionAndRange(caption, from: clip)
                                    }
                                )
                                .id(caption.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300) // Limit height so it doesn't take over the inspector
            .onChange(of: appState.playbackState.currentTime) {
                if let activeId = findActiveCaptionId(project: project, time: appState.playbackState.currentTime) {
                    withAnimation {
                        proxy.scrollTo(activeId, anchor: .center)
                    }
                }
            }
        }
    }
    
    private func isCaptionActive(_ caption: Caption, in clip: VideoClip) -> Bool {
        let playhead = appState.playbackState.currentTime.seconds
        let clipStart = clip.startTime.seconds
        let clipEnd = clipStart + clip.effectiveDuration.seconds
        
        guard playhead >= clipStart && playhead < clipEnd else { return false }
        
        let effectiveSeconds = playhead - clipStart
        let effectiveTime = CMTime(seconds: effectiveSeconds, preferredTimescale: 600)
        let originalTime = clip.originalTime(forEffectiveTime: effectiveTime).seconds
        
        return originalTime >= caption.startTime.seconds && originalTime < caption.endTime.seconds
    }
    
    private func findActiveCaptionId(project: VideoProject, time: CMTime) -> UUID? {
        let currentSeconds = time.seconds
        
        for track in project.timeline.tracks {
            for clip in track.clips {
                let clipStart = clip.startTime.seconds
                let clipEnd = clipStart + clip.effectiveDuration.seconds
                
                if currentSeconds >= clipStart && currentSeconds < clipEnd {
                    let effectiveSeconds = currentSeconds - clipStart
                    let effectiveTime = CMTime(seconds: effectiveSeconds, preferredTimescale: 600)
                    let originalTime = clip.originalTime(forEffectiveTime: effectiveTime).seconds
                    
                    for caption in clip.captions {
                        if originalTime >= caption.startTime.seconds && originalTime < caption.endTime.seconds {
                            return caption.id
                        }
                    }
                }
            }
        }
        return nil
    }
}

extension Binding where Value == VideoProject? {
    var bound: Binding<VideoProject> {
        Binding<VideoProject>(
            get: {
                return self.wrappedValue ?? VideoProject.empty()
            },
            set: { newValue in
                self.wrappedValue = newValue
            }
        )
    }
}

extension VideoProject {
    static func empty() -> VideoProject {
        VideoProject(id: UUID(), name: "Empty")
    }
}

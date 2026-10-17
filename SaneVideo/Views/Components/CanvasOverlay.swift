import AVFoundation
import SwiftUI

struct CanvasOverlay: View {
    let clip: VideoClip? // Optional: captions can be moved even when no clip is selected.
    var projectState: ProjectState

    // Local state while a gesture is in progress.
    @State private var localTranslation: CGSize = .zero
    @State private var localScale: CGFloat = 1.0

    enum InteractionTarget: Equatable {
        case none
        case clip
        case caption
        case overlay(UUID)
    }

    @State private var interactionTarget: InteractionTarget = .none

    // Local state for rotation (shared for all, but only applied to active target)
    @State private var localRotation: Angle = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Transparent hit target for gestures
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            SimultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if interactionTarget == .none {
                                            let startPoint = value.startLocation
                                            let normalizedStart = CGPoint(x: startPoint.x / geo.size.width, y: startPoint.y / geo.size.height)

                                            // Overlays sit on top, so hit-test them first.
                                            if let clip = clip {
                                                for overlay in clip.overlays.reversed() {
                                                    let rect = overlay.normalizedHitFrame

                                                    if rect.contains(normalizedStart) {
                                                        interactionTarget = .overlay(overlay.id)
                                                        return
                                                    }
                                                }
                                            }

                                            let currentOffset = projectState.currentProject?.captionOffset ?? .zero
                                            let capRect = CGRect(
                                                x: 0.1 + currentOffset.width,
                                                y: 0.8 + currentOffset.height,
                                                width: 0.8,
                                                height: 0.15
                                            )

                                            if capRect.contains(normalizedStart) {
                                                interactionTarget = .caption
                                            } else if clip != nil {
                                                interactionTarget = .clip
                                            }
                                        }

                                        localTranslation = value.translation
                                    }
                                    .onEnded { value in
                                        let dx = value.translation.width / geo.size.width
                                        let dy = value.translation.height / geo.size.height

                                        if interactionTarget == .caption {
                                            var currentOffset = projectState.currentProject?.captionOffset ?? .zero
                                            currentOffset.width += dx
                                            currentOffset.height += dy
                                            projectState.updateCaptionOffset(currentOffset)

                                        } else if case let .overlay(id) = interactionTarget, let clip = clip, let overlay = clip.overlays.first(where: { $0.id == id }) {
                                            var newOverlay = overlay
                                            newOverlay.position.x += dx
                                            newOverlay.position.y += dy
                                            projectState.updateClipOverlay(clipId: clip.id, overlay: newOverlay)

                                        } else if interactionTarget == .clip, let clip = clip {
                                            var newTransform = clip.transform
                                            newTransform.offset.x += dx
                                            newTransform.offset.y += dy
                                            projectState.updateClipTransform(clip, transform: newTransform)
                                        }

                                        localTranslation = .zero
                                        localRotation = .zero
                                        interactionTarget = .none
                                    },

                                MagnificationGesture()
                                    .onChanged { scale in
                                        if interactionTarget == .none, clip != nil {
                                            interactionTarget = .clip
                                        }
                                        localScale = scale
                                    }
                                    .onEnded { scale in
                                        if case let .overlay(id) = interactionTarget, let clip = clip, let overlay = clip.overlays.first(where: { $0.id == id }) {
                                            var newOverlay = overlay
                                            newOverlay.scale *= scale
                                            newOverlay.scale = max(0.1, min(5.0, newOverlay.scale))
                                            projectState.updateClipOverlay(clipId: clip.id, overlay: newOverlay)

                                        } else if interactionTarget == .clip, let clip = clip {
                                            var newTransform = clip.transform
                                            newTransform.scale *= scale
                                            newTransform.scale = max(0.1, min(10.0, newTransform.scale))
                                            projectState.updateClipTransform(clip, transform: newTransform)
                                        }
                                        localScale = 1.0
                                        interactionTarget = .none
                                    }
                            ),
                            RotationGesture()
                                .onChanged { angle in
                                    localRotation = angle
                                }
                                .onEnded { angle in
                                    if case let .overlay(id) = interactionTarget, let clip = clip, let overlay = clip.overlays.first(where: { $0.id == id }) {
                                        var newOverlay = overlay
                                        newOverlay.rotation += angle.radians
                                        projectState.updateClipOverlay(clipId: clip.id, overlay: newOverlay)
                                    }
                                    localRotation = .zero
                                    interactionTarget = .none
                                }
                        )
                    )

                if let project = projectState.currentProject,
                   let selectedClip = clip,
                   !selectedClip.captions.isEmpty || interactionTarget == .caption {
                    let currentOffset = project.captionOffset
                    let dragOffset = (interactionTarget == .caption) ? localTranslation : .zero
                    let normalizedDragX = dragOffset.width / geo.size.width
                    let normalizedDragY = dragOffset.height / geo.size.height

                    let finalX = 0.1 + currentOffset.width + normalizedDragX
                    let finalY = 0.8 + currentOffset.height + normalizedDragY

                    Rectangle()
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .background(Color.accentColor.opacity(0.1))
                        .overlay(Text("Captions Area").font(.caption).foregroundStyle(Color.accentColor))
                        .position(
                            x: (finalX + 0.4) * geo.size.width,
                            y: (finalY + 0.075) * geo.size.height
                        )
                        .frame(width: 0.8 * geo.size.width, height: 0.15 * geo.size.height)
                        .allowsHitTesting(false)
                        .opacity(interactionTarget == .caption ? 1.0 : 0.3)
                }

                if let clip = clip {
                    ForEach(clip.overlays) { overlay in
                        let isInteracting = (interactionTarget == .overlay(overlay.id))
                        let dragOffset = isInteracting ? localTranslation : .zero
                        let scaleFactor = isInteracting ? localScale : 1.0
                        let rotationDelta = isInteracting ? localRotation : .zero

                        let currentScale = overlay.scale * scaleFactor
                        let currentRotation = Angle(radians: overlay.rotation) + rotationDelta

                        Rectangle()
                            .strokeBorder(isInteracting ? Color.accentColor : Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .background(Color.black.opacity(0.01)) // catch hits
                            .frame(
                                width: VideoClip.VideoOverlay.defaultBoxSize.width * geo.size.width,
                                height: VideoClip.VideoOverlay.defaultBoxSize.height * geo.size.height
                            )
                            .scaleEffect(currentScale)
                            .rotationEffect(currentRotation)
                            .position(
                                x: (overlay.position.x * geo.size.width) + dragOffset.width,
                                y: (overlay.position.y * geo.size.height) + dragOffset.height
                            )
                            .allowsHitTesting(false) // Hit testing logic is manual in gesture parent
                    }
                }

                // Crosshair only while the clip is being dragged or scaled, not when merely selected.
                if interactionTarget == .clip && (localTranslation != .zero || localScale != 1.0) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .background(Circle().fill(Color.accentColor.opacity(0.2)))
                            .frame(width: 20, height: 20)
                        Rectangle().fill(Color.accentColor).frame(width: 40, height: 1)
                        Rectangle().fill(Color.accentColor).frame(width: 1, height: 40)
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .offset(x: localTranslation.width, y: localTranslation.height)
                    .scaleEffect(localScale)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

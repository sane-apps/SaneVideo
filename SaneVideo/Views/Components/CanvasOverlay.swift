import AVFoundation
import SwiftUI

struct CanvasOverlay: View {
    let clip: VideoClip? // Optional: Can interact with captions even if no clip selected
    var projectState: ProjectState

    // Local state for "Ghost" manipulation during gesture
    @State private var localTranslation: CGSize = .zero
    @State private var localScale: CGFloat = 1.0

    // Interaction Mode
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
                                            // Determine target on first drag event
                                            let startPoint = value.startLocation
                                            let normalizedStart = CGPoint(x: startPoint.x / geo.size.width, y: startPoint.y / geo.size.height)

                                            // 1. Check Overlays (Top z-index)
                                            if let clip = clip {
                                                // iterate in reverse to hit top-most first
                                                for overlay in clip.overlays.reversed() {
                                                    // Basic Hit Test (Center +/- size/2)
                                                    // We assume size is 0.5x0.2 roughly since it's not in model yet,
                                                    // OR we rely on the TextLayer rendering logic.
                                                    // For now, let's assume a standard hit box around the position
                                                    // Position is Center.
                                                    let w = 0.5 * overlay.scale
                                                    let h = 0.2 * overlay.scale
                                                    let rect = CGRect(
                                                        x: overlay.position.x - w / 2,
                                                        y: overlay.position.y - h / 2,
                                                        width: w,
                                                        height: h
                                                    )

                                                    if rect.contains(normalizedStart) {
                                                        interactionTarget = .overlay(overlay.id)
                                                        return
                                                    }
                                                }
                                            }

                                            // 2. Check Caption Geometry
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

                                        // Reset
                                        localTranslation = .zero
                                        localRotation = .zero
                                        interactionTarget = .none
                                    },

                                MagnificationGesture()
                                    .onChanged { scale in
                                        // If none selected, default to clip? Or require tap?
                                        if interactionTarget == .none, clip != nil {
                                            interactionTarget = .clip
                                        }
                                        localScale = scale
                                    }
                                    .onEnded { scale in
                                        if case let .overlay(id) = interactionTarget, let clip = clip, let overlay = clip.overlays.first(where: { $0.id == id }) {
                                            var newOverlay = overlay
                                            newOverlay.scale *= scale
                                            // Clamp
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
                                    // Don't reset interactionTarget if we want continous editing?
                                    // Gesture composition usually ends all.
                                    interactionTarget = .none
                                }
                        )
                    )

                // Visual Feedback

                // 1. Caption Box - Only show when clip has captions or actively interacting
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

                // 2. Overlays (Stickers)
                if let clip = clip {
                    ForEach(clip.overlays) { overlay in
                        let isInteracting = (interactionTarget == .overlay(overlay.id))
                        let dragOffset = isInteracting ? localTranslation : .zero
                        let scaleFactor = isInteracting ? localScale : 1.0
                        let rotationDelta = isInteracting ? localRotation : .zero

                        let currentScale = overlay.scale * scaleFactor
                        let currentRotation = Angle(radians: overlay.rotation) + rotationDelta

                        // Hit Box / Selection Box
                        Rectangle()
                            .strokeBorder(isInteracting ? Color.accentColor : Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .background(Color.black.opacity(0.01)) // catch hits
                            .frame(width: 0.5 * geo.size.width, height: 0.2 * geo.size.height) // Base size matches logic above
                            .scaleEffect(currentScale)
                            .rotationEffect(currentRotation)
                            .position(
                                x: (overlay.position.x * geo.size.width) + dragOffset.width,
                                y: (overlay.position.y * geo.size.height) + dragOffset.height
                            )
                            .allowsHitTesting(false) // Hit testing logic is manual in gesture parent
                    }
                }

                // 3. Clip Crosshair - ONLY show during ACTIVE drag/scale manipulation
                // CRITICAL FIX: Only show crosshair when actively manipulating (translation or scale changed)
                // This prevents crosshair from showing when clip is just selected but not being dragged
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

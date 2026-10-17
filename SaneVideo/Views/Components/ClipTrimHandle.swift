import SwiftUI
import AppKit
import CoreMedia

struct ClipTrimHandle: View {
    let isLeft: Bool
    let clipHeight: CGFloat
    let pixelsPerSecond: CGFloat
    let clip: VideoClip
    let playheadTime: CMTime
    let snapThreshold: CGFloat

    var onTrimStart: ((CMTime) -> Void)?
    var onTrimEnd: ((CMTime) -> Void)?

    @Binding var isDragging: Bool
    @Binding var trimOffset: CGFloat

    var onHoverChange: ((Bool) -> Void)?

    var body: some View {
        ZStack {
            // Touch target - Transparent but wide for easy grabbing
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.01))
                .frame(width: 20, height: clipHeight)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(width: 12, height: clipHeight * 0.6)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .overlay(
                    HStack(spacing: 2) {
                        ForEach(0..<3) { _ in
                            Capsule()
                                .fill(Theme.Colors.accent)
                                .frame(width: 2, height: 12)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.Colors.accent, lineWidth: 1)
                )
        }
        // Offset the handle during a drag so it stays under the cursor as the clip resizes.
        .offset(x: isDragging ? trimOffset : 0)
        .contentShape(Rectangle())
        .cursor(NSCursor.resizeLeftRight)
        .onHover { hovering in
            // Tell the parent when the handle is hovered so the clip doesn't scale while the user grabs it.
            AppLogger.uiLog.debug("🔧 Trim handle hover: isLeft=\(isLeft), hovering=\(hovering)")
            onHoverChange?(hovering)
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    AppLogger.uiLog.info("🔧 Trim handle drag started: isLeft=\(isLeft), translation=\(value.translation.width)")
                    isDragging = true
                    trimOffset = value.translation.width
                }
                .onEnded { value in
                    AppLogger.uiLog.info("🔧 Trim handle drag ended: isLeft=\(isLeft), finalTranslation=\(value.translation.width)")
                    var deltaSeconds = value.translation.width / pixelsPerSecond

                    deltaSeconds = applyPlayheadSnapping(
                        deltaSeconds: deltaSeconds,
                        isLeft: isLeft
                    )

                    let delta = CMTime(seconds: deltaSeconds, preferredTimescale: 600)

                    if isLeft {
                        isDragging = false
                        let clampedStart = Self.resolvedTrimStart(for: clip, delta: delta)
                        onTrimStart?(clampedStart)
                        trimOffset = 0
                    } else {
                        isDragging = false
                        let clampedEnd = Self.resolvedTrimEnd(for: clip, delta: delta)
                        onTrimEnd?(clampedEnd)
                        trimOffset = 0
                    }
                }
        )
        .onTapGesture {
            // Do nothing - let the drag handle the interaction
        }
    }

    static func resolvedTrimStart(for clip: VideoClip, delta: CMTime) -> CMTime {
        let newStart = CMTimeAdd(clip.trimStart, delta)
        return max(
            .zero,
            min(newStart, CMTimeSubtract(clip.trimEnd, CMTime(seconds: 0.1, preferredTimescale: 600)))
        )
    }

    static func resolvedTrimEnd(for clip: VideoClip, delta: CMTime) -> CMTime {
        let newEnd = CMTimeAdd(clip.trimEnd, delta)
        return min(
            clip.duration,
            max(newEnd, CMTimeAdd(clip.trimStart, CMTime(seconds: 0.1, preferredTimescale: 600)))
        )
    }

    private func applyPlayheadSnapping(deltaSeconds: Double, isLeft: Bool) -> Double {
        var result = deltaSeconds

        if isLeft {
            let proposedTrimStart = clip.trimStart.seconds + deltaSeconds
            let playheadRelative = playheadTime.seconds - clip.startTime.seconds
            let distanceToPlayhead = abs(proposedTrimStart - playheadRelative)
            if distanceToPlayhead * pixelsPerSecond < snapThreshold {
                result = playheadRelative - clip.trimStart.seconds
            }
        } else {
            let proposedTrimEnd = clip.trimEnd.seconds + deltaSeconds
            let playheadRelative = playheadTime.seconds - clip.startTime.seconds
            let distanceToPlayhead = abs(proposedTrimEnd - playheadRelative)
            if distanceToPlayhead * pixelsPerSecond < snapThreshold {
                result = playheadRelative - clip.trimEnd.seconds
            }
        }

        return result
    }
}

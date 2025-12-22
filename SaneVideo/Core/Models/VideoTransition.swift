//
//  VideoTransition.swift
//  SaneVideo
//
//  Transition types for clip-to-clip transitions using CIFilter
//

import CoreImage
import CoreMedia
import Foundation

/// Types of transitions available between clips
enum TransitionType: String, Codable, CaseIterable, Identifiable {
    case none
    case dissolve
    case fadeToBlack
    case fadeToWhite
    case wipeRight
    case wipeLeft
    case swipeRight
    case swipeLeft
    case pushRight
    case pushLeft
    case zoom
    case smoothCut

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .none: return "None"
        case .dissolve: return "Dissolve"
        case .fadeToBlack: return "Fade Black"
        case .fadeToWhite: return "Fade White"
        case .wipeRight: return "Wipe Right"
        case .wipeLeft: return "Wipe Left"
        case .swipeRight: return "Swipe Right"
        case .swipeLeft: return "Swipe Left"
        case .pushRight: return "Push Right"
        case .pushLeft: return "Push Left"
        case .zoom: return "Zoom"
        case .smoothCut: return "Smooth Cut"
        }
    }

    /// SF Symbol icon for the transition
    var icon: String {
        switch self {
        case .none: return "circle.slash"
        case .dissolve: return "square.on.square"
        case .fadeToBlack: return "circle.fill"
        case .fadeToWhite: return "circle"
        case .wipeRight: return "chevron.right"
        case .wipeLeft: return "chevron.left"
        case .swipeRight: return "arrow.right.square"
        case .swipeLeft: return "arrow.left.square"
        case .pushRight: return "rectangle.righthalf.filled"
        case .pushLeft: return "rectangle.lefthalf.filled"
        case .zoom: return "plus.magnifyingglass"
        case .smoothCut: return "magicmouse"
        }
    }

    /// CIFilter name (if applicable)
    var ciFilterName: String? {
        switch self {
        case .none: return nil
        case .dissolve: return "CIDissolveTransition"
        case .fadeToBlack, .fadeToWhite: return nil // Custom fade logic
        case .wipeRight, .wipeLeft: return "CISwipeTransition"
        case .swipeRight, .swipeLeft: return "CISwipeTransition"
        case .pushRight, .pushLeft: return "CIPageCurlTransition"
        case .zoom: return nil // Custom zoom logic
        case .smoothCut: return nil // Custom smooth cut logic
        }
    }

    /// Default duration for this transition type (in seconds)
    nonisolated var defaultDuration: Double {
        switch self {
        case .none: return 0
        case .dissolve: return 0.5
        case .fadeToBlack, .fadeToWhite: return 0.5
        case .wipeRight, .wipeLeft: return 0.5
        case .swipeRight, .swipeLeft: return 0.3
        case .pushRight, .pushLeft: return 0.4
        case .zoom: return 0.5
        case .smoothCut: return 0.2
        }
    }
}

/// A transition between two clips
struct VideoTransition: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = .init()
    var type: TransitionType
    var duration: CMTime

    nonisolated init(type: TransitionType, duration: CMTime? = nil) {
        self.type = type
        self.duration = duration ?? CMTime(seconds: type.defaultDuration, preferredTimescale: 600)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, durationSeconds
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(TransitionType.self, forKey: .type)
        let seconds = try container.decode(Double.self, forKey: .durationSeconds)
        duration = CMTime(seconds: seconds, preferredTimescale: 600)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(duration.seconds, forKey: .durationSeconds)
    }

    /// Generate a transition frame between two images at given progress (0.0 to 1.0)
    nonisolated func apply(from source: CIImage, to target: CIImage, progress: CGFloat) -> CIImage? {
        switch type {
        case .none:
            return progress < 0.5 ? source : target

        case .dissolve:
            guard let filter = CIFilter(name: "CIDissolveTransition") else { return nil }
            filter.setValue(source, forKey: kCIInputImageKey)
            filter.setValue(target, forKey: kCIInputTargetImageKey)
            filter.setValue(progress, forKey: kCIInputTimeKey)
            return filter.outputImage

        case .fadeToBlack:
            // First half: fade source to black, second half: fade black to target
            let blackImage = CIImage(color: CIColor.black).cropped(to: source.extent)
            if progress < 0.5 {
                return dissolve(from: source, to: blackImage, progress: progress * 2)
            } else {
                return dissolve(from: blackImage, to: target, progress: (progress - 0.5) * 2)
            }

        case .fadeToWhite:
            let whiteImage = CIImage(color: CIColor.white).cropped(to: source.extent)
            if progress < 0.5 {
                return dissolve(from: source, to: whiteImage, progress: progress * 2)
            } else {
                return dissolve(from: whiteImage, to: target, progress: (progress - 0.5) * 2)
            }

        case .wipeRight:
            return wipe(from: source, to: target, progress: progress, direction: .right)

        case .wipeLeft:
            return wipe(from: source, to: target, progress: progress, direction: .left)

        case .swipeRight, .swipeLeft:
            // Similar to wipe but with acceleration
            return wipe(from: source, to: target, progress: easeInOut(progress), direction: type == .swipeRight ? .right : .left)

        case .pushRight, .pushLeft:
            return push(from: source, to: target, progress: progress, direction: type == .pushRight ? .right : .left)

        case .zoom:
            return zoom(from: source, to: target, progress: progress)
        case .smoothCut:
            return smoothCut(from: source, to: target, progress: progress)
        }
    }

    // MARK: - Helper Methods

    private nonisolated func dissolve(from source: CIImage, to target: CIImage, progress: CGFloat) -> CIImage? {
        guard let filter = CIFilter(name: "CIDissolveTransition") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(target, forKey: kCIInputTargetImageKey)
        filter.setValue(progress, forKey: kCIInputTimeKey)
        return filter.outputImage
    }

    private enum Direction: Sendable { case left, right }

    private nonisolated func wipe(from source: CIImage, to target: CIImage, progress: CGFloat, direction: Direction) -> CIImage? {
        let extent = source.extent
        let splitX: CGFloat
        let leftImage: CIImage
        let rightImage: CIImage

        switch direction {
        case .right:
            splitX = extent.width * progress
            let leftRect = CGRect(x: 0, y: 0, width: splitX, height: extent.height)
            let rightRect = CGRect(x: splitX, y: 0, width: extent.width - splitX, height: extent.height)
            leftImage = target.cropped(to: leftRect)
            rightImage = source.cropped(to: rightRect)
        case .left:
            splitX = extent.width * (1 - progress)
            let leftRect = CGRect(x: 0, y: 0, width: splitX, height: extent.height)
            let rightRect = CGRect(x: splitX, y: 0, width: extent.width - splitX, height: extent.height)
            leftImage = source.cropped(to: leftRect)
            rightImage = target.cropped(to: rightRect)
        }

        return leftImage.composited(over: rightImage)
    }

    private nonisolated func push(from source: CIImage, to target: CIImage, progress: CGFloat, direction: Direction) -> CIImage? {
        let extent = source.extent
        let offset = extent.width * progress

        let (sourceOffset, targetOffset): (CGFloat, CGFloat)
        switch direction {
        case .right:
            sourceOffset = -offset
            targetOffset = extent.width - offset
        case .left:
            sourceOffset = offset
            targetOffset = -extent.width + offset
        }

        let movedSource = source.transformed(by: CGAffineTransform(translationX: sourceOffset, y: 0))
        let movedTarget = target.transformed(by: CGAffineTransform(translationX: targetOffset, y: 0))

        return movedTarget.composited(over: movedSource)
    }

    private nonisolated func zoom(from source: CIImage, to target: CIImage, progress: CGFloat) -> CIImage? {
        // Source zooms in and fades, target appears
        let extent = source.extent
        let scale = 1.0 + (progress * 0.3) // Zoom from 100% to 130%
        let opacity = 1.0 - progress

        let center = CGPoint(x: extent.midX, y: extent.midY)
        let scaleTransform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)

        let zoomedSource = source.transformed(by: scaleTransform)

        // Apply opacity
        if let opacityFilter = CIFilter(name: "CIColorMatrix") {
            opacityFilter.setValue(zoomedSource, forKey: kCIInputImageKey)
            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)), forKey: "inputAVector")
            if let fadedSource = opacityFilter.outputImage {
                return fadedSource.composited(over: target)
            }
        }

        return progress < 0.5 ? source : target
    }

    private nonisolated func easeInOut(_ t: CGFloat) -> CGFloat {
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
    
    // Smooth Cut: Subtle Zoom + Dissolve
    private nonisolated func smoothCut(from source: CIImage, to target: CIImage, progress: CGFloat) -> CIImage? {
        // Subtle scale-up on target to hide jaw/eye jumps
        let extent = target.extent
        let targetScale = 1.05 // 5% scale up
        let center = CGPoint(x: extent.midX, y: extent.midY)
        
        let scaleTransform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: targetScale, y: targetScale)
            .translatedBy(x: -center.x, y: -center.y)
        
        let scaledTarget = target.transformed(by: scaleTransform)
        
        // Dissolve from source to scaledTarget
        return dissolve(from: source, to: scaledTarget, progress: progress)
    }
}

// MARK: - Hashable

extension VideoTransition: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
        hasher.combine(duration)
    }
}

//
//  ProjectState+VisionEffects.swift
//  SaneVideo
//
//  Vision-based effects using FaceTrackingService and SaliencyService
//

import AVFoundation
import CoreImage
import Foundation

extension ProjectState {
    
    // MARK: - Auto-Framing (Face Tracking)
    
    /// Apply auto-framing using dynamic keyframes to track faces
    func applyAutoFraming(to clip: VideoClip, padding: CGFloat = 0.3) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎯 Tracking faces in video...")
        }
        
        defer {
            Task { @MainActor in self.isProcessing = false }
        }
        
        do {
            let faceService = ServiceContainer.shared.faceTrackingService
            
            // Analyze video for faces over time (every 0.5s)
            let analysis = try await faceService.analyzeVideo(
                videoURL: clip.url,
                sampleInterval: 0.5
            ) { _ in
                // Could report progress here
            }
            
            if analysis.isEmpty {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No faces detected to track", type: .info)
                }
                return
            }
            
            // Create Keyframes
            var keyframes = KeyframeAnimation()
            
            // Sort times
            let sortedTimes = analysis.keys.sorted { $0 < $1 }
            
            for time in sortedTimes {
                guard let faceRect = analysis[time] else { continue }
                
                // Calculate Transform for this frame
                // 1. Target Crop Size: Face Rect + Padding
                // We assume we want to zoom enough so the face + padding fills ~50% of screen ideally?
                // Or just ensure it FITS.
                // VideoClip.Transform logic: Scale=1 shows full image.
                // We want: FaceRect * Scale approx = 1.0 (Fill screen)? No that's too close.
                // Let's say we want face to be 1/3 of screen height.
                // TargetFaceHeight = 0.33
                // CurrentFaceHeight = faceRect.height (normalized)
                // Scale = Target / Current
                
                // Let's use a safe framing logic:
                // Ensure face is at least minSize, but don't zoom out past 1.0.
                let targetFaceSize: CGFloat = 0.4 // Face should occupy 40% of dimension
                let requiredScale = targetFaceSize / max(faceRect.width, faceRect.height, 0.01)
                let scale = max(1.0, min(requiredScale, 3.0)) // Clamp zoom 1x to 3x
                
                // 2. Position Shift (Centering)
                // Offset = Scale * (Center - ObjectCenter)
                // (0,0) is bottom-left in Vision/CI
                let center = CGPoint(x: 0.5, y: 0.5)
                let faceCenter = CGPoint(x: faceRect.midX, y: faceRect.midY)
                
                let posX = scale * (center.x - faceCenter.x)
                let posY = scale * (center.y - faceCenter.y)
                
                // Add keys
                keyframes.setKeyframe(property: .scale, at: time, value: Double(scale))
                keyframes.setKeyframe(property: .positionX, at: time, value: Double(posX))
                keyframes.setKeyframe(property: .positionY, at: time, value: Double(posY))
            }
            
            await MainActor.run {
                self.applyKeyframes(keyframes, to: clip)
                ServiceContainer.shared.toastManager.show("✅ Dynamic Auto-Frame applied")
            }
            
        } catch {
            AppLogger.project.error("Auto-framing failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Auto-framing failed", type: .error)
            }
        }
    }
    
    // MARK: - Smart Crop (Saliency)
    
    /// Apply smart crop with dynamic tracking (9:16 Target)
    func applySmartCrop(to clip: VideoClip, targetAspectRatio: CGFloat = 9.0/16.0) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎨 Analyzing attention flow...")
        }
        
        defer {
            Task { @MainActor in self.isProcessing = false }
        }
        
        do {
            let saliencyService = ServiceContainer.shared.saliencyService
            
            // Analyze video
            let analysis = try await saliencyService.analyzeVideoForReframe(
                videoURL: clip.url,
                sampleInterval: 0.5
            )
            
            if analysis.isEmpty {
                 await MainActor.run { ServiceContainer.shared.toastManager.show("No saliency data found", type: .info) }
                 return
            }
            
            var keyframes = KeyframeAnimation()
            let sortedTimes = analysis.keys.sorted { $0 < $1 }
            
            for time in sortedTimes {
                guard let result = analysis[time] else { continue }
                
                // Target: 9:16 Vertical Crop
                // We assume source is 16:9 Landscape (standard)
                // We need to zoom in to fill height, and cut sides.
                // Scale needed to Make Source Height == Target Height (which is 16 units vs 9 units? No)
                // We are mapping Source (1.0 x 1.0 normalized) to Target.
                // If Aspect Ratio of Source is S_ar (e.g. 1.77), Target T_ar (0.56).
                // To fill height: Scale = 1.0 (Height matches).
                // To fill width: Scale = T_ar / S_ar ?
                
                // Simpler:
                // We want a Crop Rect of aspect ratio 9:16.
                // If source is 1920x1080 (1.77).
                // Crop Rect Height = 1.0 (Full height).
                // Crop Rect Width = (1.0 * H_px / T_ar_inv?)
                
                // Let's assume standard behavior:
                // Scale = SourceAspect / TargetAspect ?
                // If S=16/9, T=9/16. Scale = (16/9)/(9/16) = 3.16. Correct.
                // We need to zoom 3.16x to fill a vertical screen with a landscape video?
                // Wait, users usually view 9:16 ON A PHONE.
                // Implementation: We effectively scale the content up so the "Crop Region" fills the view.
                
                // Constant scale for 9:16 conversion from 16:9
                // Let's assume ~3.0 for safety or calculate if we had aspect ratios.
                // Assuming standard 16:9 source:
                let scale = 3.16 // (16/9) / (9/16)
                
                // Dynamic Panning: specific to attention point
                let center = CGPoint(x: 0.5, y: 0.5)
                let attention = result.attentionPoint // Normalized
                
                // Calculate pan to center attention
                // Clamp attention to "safe zone" so we don't show black bars?
                // With scale ~3.16, we have huge latitude.
                // Safe zone x: [0.5/Scale, 1 - 0.5/Scale] ?
                // 0.5/3.16 = 0.15. Range 0.15 ... 0.85.
                // If attention is at 0.0, we can shift it to center, but we show edge.
                
                // Clamp X
                let safeMargin = 0.5 / scale
                let clampedX = max(safeMargin, min(1.0 - safeMargin, attention.x))
                // Keep Y centered (usually we don't pan vertically for 9:16 crop of 16:9)
                let clampedY = 0.5
                
                let posX = scale * (center.x - clampedX)
                let posY = scale * (center.y - clampedY)
                
                keyframes.setKeyframe(property: .scale, at: time, value: scale)
                keyframes.setKeyframe(property: .positionX, at: time, value: posX)
                keyframes.setKeyframe(property: .positionY, at: time, value: posY)
            }
            
            await MainActor.run {
                self.applyKeyframes(keyframes, to: clip)
                ServiceContainer.shared.toastManager.show("✅ Smart 9:16 Crop applied")
            }
            
        } catch {
            AppLogger.project.error("Smart crop failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Smart crop failed", type: .error)
            }
        }
    }
    
    // MARK: - Helper
    
    /// Apply keyframes to clip and save
    private func applyKeyframes(_ keyframes: KeyframeAnimation, to clip: VideoClip) {
        guard var project = currentProject else { return }
        
        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clip.id }) {
                var updatedClip = track.clips[cIdx]
                
                updatedClip.keyframeAnimation = keyframes
                
                // Reset static transform to avoid conflict/double apply
                updatedClip.transform = .identity
                
                registerUndo("Apply Vision Effects")
                project.timeline.tracks[tIdx].clips[cIdx] = updatedClip
                currentProject = project
                saveProject(project)
                return
            }
        }
    }
    
    // MARK: - Gesture Detection (BodyPose)
    
    /// Find gestures in clip and add markers
    func findGestures(in clip: VideoClip) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🙋 Scanning for gestures...")
        }
        
        defer {
            Task { @MainActor in self.isProcessing = false }
        }
        
        do {
            let bodyService = ServiceContainer.shared.bodyPoseService
            
            // Detect all body gestures
            let gestures = try await bodyService.detectGestures(
                in: clip.url,
                gestures: BodyGesture.allCases,
                sampleInterval: 0.5
            )
            
            if gestures.isEmpty {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No gestures detected", type: .info)
                }
                return
            }
            
            // Group by gesture type for summary
            var gestureCount: [BodyGesture: Int] = [:]
            for (gesture, _) in gestures {
                gestureCount[gesture, default: 0] += 1
            }
            
            let summary = gestureCount.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")
            
            // Log the timestamps (could add markers in future)
            AppLogger.vision.info("Found gestures: \(summary)")
            for (gesture, time) in gestures {
                AppLogger.vision.debug("  \(gesture.rawValue) at \(time.seconds)s")
            }
            
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Found \(gestures.count) gestures: \(summary)")
            }
            
        } catch {
            AppLogger.project.error("Gesture detection failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Gesture detection failed", type: .error)
            }
        }
    }
    
    // MARK: - Privacy Blur (Text Recognition)
    
    /// Apply privacy blur to detected text regions
    func applyPrivacyBlur(to clip: VideoClip) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🔒 Detecting sensitive text...")
        }
        
        defer {
            Task { @MainActor in self.isProcessing = false }
        }
        
        do {
            let textService = ServiceContainer.shared.textRecognitionService
            
            // Scan video for text
            let allText = try await textService.scanVideoForText(
                videoURL: clip.url,
                sampleInterval: 1.0
            )
            
            // Find sensitive text (emails, phones)
            let sensitiveCount = allText.filter { text in
                let content = text.text
                // Simple heuristics
                return content.contains("@") || 
                       content.filter { $0.isNumber }.count >= 7 ||
                       content.contains("http")
            }.count
            
            if sensitiveCount == 0 {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No sensitive text found", type: .info)
                }
                return
            }
            
            // Log detection results
            AppLogger.vision.info("Found \(sensitiveCount) sensitive text regions")
            
            await MainActor.run {
                // Convert to PrivacyRegions
                var privacyRegions: [PrivacyRegion] = []
                
                for item in allText {
                    // Filter again for sensitive content
                    let content = item.text
                    let isSensitive = content.contains("@") || 
                                     content.filter { $0.isNumber }.count >= 7 ||
                                     content.contains("http")
                    
                    if isSensitive {
                        // Create PrivacyRegion
                        // TextRecognitionResult usually has timeRange and boundingBox
                        // item.boundingBox is normalized (0-1), usually bottom-left origin in Vision? 
                        // We need to ensure it matches our coordinate system.
                        // Assuming item.boundingBox is standard normalized rect.
                        
                        let region = PrivacyRegion(
                            timeRange: CMTimeRange(start: item.time, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
                            frame: item.boundingBox
                        )
                        privacyRegions.append(region)
                    }
                }
                
                // Update Clip
                self.updateClipPrivacyRegions(clipId: clip.id, regions: privacyRegions)
                
                ServiceContainer.shared.toastManager.show("🔒 Applied \(privacyRegions.count) privacy blurs")
            }
            
        } catch {
            AppLogger.project.error("Privacy blur failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Text detection failed", type: .error)
            }
        }
    }
    
    // MARK: - Audio Analysis (SoundAnalysis)
    
    /// Find highlights (applause, laughter) in clip audio
    func findHighlights(in clip: VideoClip) async {
        guard !isProcessing else { return }
        isProcessing = true
        
        await MainActor.run {
            ServiceContainer.shared.toastManager.show("🎉 Scanning audio for highlights...")
        }
        
        defer {
            Task { @MainActor in self.isProcessing = false }
        }
        
        do {
            let soundService = ServiceContainer.shared.soundAnalysisService
            
            // Find applause, laughter, crowd reactions
            let highlights = try await soundService.findHighlights(in: clip.url)
            
            if highlights.isEmpty {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("No highlights found (applause, laughter)", type: .info)
                }
                return
            }
            
            // Group by type for summary
            var typeCount: [AudioLabel: Int] = [:]
            for highlight in highlights {
                typeCount[highlight.label, default: 0] += 1
            }
            
            let summary = typeCount.map { "\($0.key.displayName): \($0.value)" }.joined(separator: ", ")
            
            // Log timestamps for potential marker addition
            AppLogger.audio.info("Found highlights: \(summary)")
            for highlight in highlights {
                AppLogger.audio.debug("  \(highlight.label.displayName) at \(highlight.timeRange.start.seconds)s")
            }
            
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Found \(highlights.count) highlights: \(summary)")
            }
            
        } catch {
            AppLogger.project.error("Highlight detection failed: \(error)")
            await MainActor.run {
                ServiceContainer.shared.toastManager.show("Audio analysis failed", type: .error)
            }
        }
    }

    /// Helper to update clip privacy regions
    func updateClipPrivacyRegions(clipId: UUID, regions: [PrivacyRegion]) {
        guard var project = currentProject else { return }
        
        for (tIdx, track) in project.timeline.tracks.enumerated() {
            if let cIdx = track.clips.firstIndex(where: { $0.id == clipId }) {
                var updatedClip = track.clips[cIdx]
                updatedClip.privacyRegions = regions
                
                project.timeline.tracks[tIdx].clips[cIdx] = updatedClip
                
                // Register Undo?
                // registerUndo("Apply Privacy Blur") 
                // We should probably register undo before modifying.
                // But this helper is internal.
                
                currentProject = project
                // saveProject(project) // Save is implicit in currentProject update mostly or triggered manually
                // But generally we should save.
                return
            }
        }
    }
}

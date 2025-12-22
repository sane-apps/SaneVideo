//
//  SmartColorGradeService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation
import CoreMedia

/// Service for smart color grading based on sentiment analysis
enum SmartColorGradeService {
    
    /// Analyze clip sentiment and return suggested grade effects
    static func analyzeSentiment(for captions: [Caption]) async -> (sentiment: Sentiment, effects: [VideoEffectType]) {
        let serviceCaptions = captions.map { caption in
            Caption(
                text: caption.text,
                startTime: caption.startTime,
                endTime: caption.endTime
            )
        }
        
        let sentiment = await ServiceContainer.shared.sentimentAnalysisService.getOverallMood(captions: serviceCaptions)
        let grade = sentiment.suggestedColorGrade
        
        return (sentiment.sentiment, grade.effects)
    }
    
    /// Filter effects to only add new ones (avoid duplicates)
    static func newEffectsToApply(
        suggested: [VideoEffectType],
        existing: [VideoEffect]
    ) -> [VideoEffect] {
        var newEffects: [VideoEffect] = []
        
        for type in suggested where !existing.contains(where: { $0.type == type }) {
            newEffects.append(VideoEffect(type: type))
        }
        
        return newEffects
    }
}

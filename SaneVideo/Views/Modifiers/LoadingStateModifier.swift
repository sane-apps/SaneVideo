//
//  LoadingStateModifier.swift
//  SaneVideo
//
//  Consistent loading state UI patterns
//

import SwiftUI

/// Standardized loading indicator
struct LoadingIndicator: View {
    let message: String?
    let progress: Double?
    
    init(message: String? = nil, progress: Double? = nil) {
        self.message = message
        self.progress = progress
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if let progress = progress {
                // Progress bar style
                VStack(spacing: 8) {
                    if let message = message {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(Color.stone)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.stone.opacity(0.1))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(Theme.Colors.accentGradient)
                                .frame(width: geo.size.width * CGFloat(progress), height: 4)
                                .animation(.smooth(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Color.stone)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                // Spinner style
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    if let message = message {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(Color.stone)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.Dimensions.cornerRadius)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

/// ViewModifier for adding loading overlay
struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    let message: String?
    let progress: Double?
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isLoading {
                    LoadingIndicator(message: message, progress: progress)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLoading)
                }
            }
    }
}

/// ViewModifier for inline loading state
struct InlineLoadingModifier: ViewModifier {
    let isLoading: Bool
    let message: String?
    let progress: Double?
    
    func body(content: Content) -> some View {
        Group {
            if isLoading {
                LoadingIndicator(message: message, progress: progress)
            } else {
                content
            }
        }
        .animation(.smooth(duration: 0.2), value: isLoading)
    }
}

extension View {
    /// Adds a loading overlay when isLoading is true
    func loadingOverlay(isLoading: Bool, message: String? = nil, progress: Double? = nil) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message, progress: progress))
    }
    
    /// Replaces content with loading indicator when isLoading is true
    func inlineLoading(isLoading: Bool, message: String? = nil, progress: Double? = nil) -> some View {
        modifier(InlineLoadingModifier(isLoading: isLoading, message: message, progress: progress))
    }
}

//
//  FirstLaunchView.swift
//  SaneVideo
//
//  Welcome screen for first-time users
//

import SwiftUI

/// First launch onboarding view
struct FirstLaunchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    
    private let steps = [
        OnboardingStep(
            icon: "video.fill",
            title: "Record & Edit in One App",
            description: "Capture your screen, camera, or both. Then edit with professional tools—all in one place.",
            color: .blue
        ),
        OnboardingStep(
            icon: "wand.and.stars",
            title: "AI-Powered Magic Fix",
            description: "Remove silence, cut filler words, and enhance your videos automatically—100% on your Mac.",
            color: .purple
        ),
        OnboardingStep(
            icon: "lock.shield.fill",
            title: "Privacy First",
            description: "All AI processing happens on-device. Your videos never leave your Mac.",
            color: .green
        ),
        OnboardingStep(
            icon: "bolt.fill",
            title: "Optimized for Apple Silicon",
            description: "Built exclusively for M1+ Macs. Fast exports, smooth editing, and thermal intelligence.",
            color: .orange
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.smoothUI, value: currentStep)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 30)
            
            // Content
            TabView(selection: $currentStep) {
                ForEach(0..<steps.count, id: \.self) { index in
                    OnboardingStepView(step: steps[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 400)
            
            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation(.smoothUI) {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation(.smoothUI) {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 600, height: 600)
        .background(.ultraThinMaterial)
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct OnboardingStepView: View {
    let step: OnboardingStep
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: step.icon)
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [step.color, step.color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .smoothAppear()
            
            Text(step.title)
                .font(.title)
                .fontWeight(.bold)
                .smoothAppear()
            
            Text(step.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .smoothAppear()
        }
    }
}


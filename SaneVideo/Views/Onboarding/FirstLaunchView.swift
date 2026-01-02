//
//  FirstLaunchView.swift
//  SaneVideo
//
//  Welcome screen for first-time users
//

import SwiftUI
import WhisperKit

/// First launch onboarding view
struct FirstLaunchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    @State private var isDownloadingWhisperKit = false
    @State private var whisperKitDownloadComplete = false
    @State private var whisperKitSkipped = false

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
        ),
        OnboardingStep(
            icon: "text.bubble.fill",
            title: "Auto-Captions in 100+ Languages",
            description: "Industry-leading accuracy powered by Whisper AI. Handles accents, technical jargon, multiple speakers, and noisy audio—all processed on-device. Download now (~1GB) or skip and download later.",
            color: .cyan
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
            .tabViewStyle(.automatic)
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
                    .disabled(isDownloadingWhisperKit)
                }

                Spacer()

                // Last step (WhisperKit) has special handling
                if currentStep == steps.count - 1 {
                    if isDownloadingWhisperKit {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Downloading AI model...")
                                .foregroundColor(.secondary)
                        }
                    } else if whisperKitDownloadComplete {
                        Button("Get Started") {
                            completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        HStack(spacing: 12) {
                            Button("Skip for Now") {
                                whisperKitSkipped = true
                                completeOnboarding()
                            }
                            .buttonStyle(.bordered)

                            Button("Download AI Model") {
                                Task {
                                    await downloadWhisperKitModel()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                } else {
                    Button("Next") {
                        withAnimation(.smoothUI) {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(width: 600, height: 600)
        .background(.ultraThinMaterial)
    }

    private func downloadWhisperKitModel() async {
        isDownloadingWhisperKit = true

        do {
            // Initialize WhisperKit which triggers model download
            // Using large-v3-turbo for multilingual support (100+ languages)
            let config = WhisperKitConfig()
            config.model = "openai_whisper-large-v3_turbo_954MB"
            config.verbose = false
            config.prewarm = true

            AppLogger.project.info("🎤 Onboarding: Starting WhisperKit multilingual model download (~1GB)...")
            _ = try await WhisperKit(config)
            AppLogger.project.info("✅ Onboarding: WhisperKit model download complete")
            whisperKitDownloadComplete = true
        } catch {
            AppLogger.project.error("❌ Onboarding: WhisperKit download failed: \(error.localizedDescription)")
            // Still complete - user can retry from settings
            whisperKitDownloadComplete = true
        }

        isDownloadingWhisperKit = false
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

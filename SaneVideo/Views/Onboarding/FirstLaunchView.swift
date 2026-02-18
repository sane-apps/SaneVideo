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

    /// Index of the WhisperKit download step (last item in steps array)
    private var whisperKitStepIndex: Int { steps.count - 1 }

    /// Index of the Sane Promise page (after all steps)
    private var promisePageIndex: Int { steps.count }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator (steps + promise page)
            HStack {
                ForEach(0 ..< steps.count + 1, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.stone.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.smoothUI, value: currentStep)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 30)

            // Content
            TabView(selection: $currentStep) {
                ForEach(0 ..< steps.count, id: \.self) { index in
                    OnboardingStepView(step: steps[index])
                        .tag(index)
                }
                SanePromisePage()
                    .tag(steps.count)
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

                // Promise page (final) — just "Get Started"
                if currentStep == promisePageIndex {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                // WhisperKit step — special download handling
                else if currentStep == whisperKitStepIndex {
                    if isDownloadingWhisperKit {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Downloading AI model...")
                                .foregroundColor(Color.stone)
                        }
                    } else if whisperKitDownloadComplete || whisperKitSkipped {
                        Button("Next") {
                            withAnimation(.smoothUI) {
                                currentStep = promisePageIndex
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        HStack(spacing: 12) {
                            Button("Skip for Now") {
                                whisperKitSkipped = true
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
                }
                // All other steps — simple Next button
                else {
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
                .foregroundColor(Color.stone)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .smoothAppear()
        }
    }
}

// MARK: - Sane Promise (Brand Philosophy)

struct SanePromisePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Our Sane Philosophy")
                .font(.system(size: 32, weight: .bold))

            VStack(spacing: 8) {
                Text("\"For God has not given us a spirit of fear,")
                    .font(.system(size: 17))
                    .italic()
                Text("but of power and of love and of a sound mind.\"")
                    .font(.system(size: 17))
                    .italic()
                Text("— 2 Timothy 1:7")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
            }

            HStack(spacing: 20) {
                SanePillarCard(
                    icon: "bolt.fill",
                    color: .yellow,
                    title: "Power",
                    description: "Your data stays on your device. No cloud, no tracking."
                )

                SanePillarCard(
                    icon: "heart.fill",
                    color: .pink,
                    title: "Love",
                    description: "Built to serve you. No dark patterns or manipulation."
                )

                SanePillarCard(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "Sound Mind",
                    description: "Calm, focused design. No clutter or anxiety."
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .padding(32)
    }
}

private struct SanePillarCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 18, weight: .semibold))

            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.08))
        .cornerRadius(12)
    }
}

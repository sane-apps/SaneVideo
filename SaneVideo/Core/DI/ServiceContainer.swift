//
//  ServiceContainer.swift
//  SaneVideo
//
//  Dependency Injection container for testable, loosely-coupled services
//  Best practice: Use this instead of singletons for non-view services
//

import AVFoundation
import Foundation

/// Central registry for application services
/// Use initializer injection to provide these to classes that need them
@MainActor
final class ServiceContainer {
    // MARK: - Singleton (Only access point)
    
    static let shared = ServiceContainer()
    
    // MARK: - Core Services
    
    // MARK: - Core Services
    
    var cameraService: CameraServiceProtocol
    let projectStore: ProjectStoreProtocol
    let exportService: ExportServiceProtocol

    let thumbnailService: ThumbnailGeneratorService
    let silenceDetector: SilenceDetector
    var audioService: AudioService
    let permissionManager: PermissionManager
    
    // MARK: - UI Services
    
    let toastManager: ToastManager
    let hapticsManager: HapticsManager
    let soundManager: SoundManager
    let errorPresenter: ErrorPresenter
    
    // MARK: - Export Services
    
    let youtubeService: YouTubeService
    let pdfService: PDFGeneratorService
    let ffmpegService: FFmpegService
    let shareLinkService: ShareLinkService
    
    // MARK: - Audio/Voice Services
    
    let voiceoverService: VoiceoverService
    let waveformService: WaveformService
    let soundAnalysisService: SoundAnalysisService
    let voiceIsolationService: VoiceIsolationService
    
    // MARK: - AI/ML Services
    
    let aiService: AIService
    let appleSpeechService: AppleSpeechService
    let smartFillerDetector: SmartFillerDetector
    let sentimentAnalysisService: SentimentAnalysisService
    
    // MARK: - Vision Services
    
    let visionOrchestrator: VisionOrchestrator
    
    @available(macOS 15.0, *)
    var translationService: TranslationService {
        TranslationService.shared
    }
    
    // MARK: - Vision Services
    
    let bodyPoseService: BodyPoseService
    let faceTrackingService: FaceTrackingService
    let personSegmentationService: PersonSegmentationService
    let saliencyService: SaliencyService
    let textRecognitionService: TextRecognitionService
    let generativeVisionService: GenerativeVisionService
    let smartThumbnailService: SmartThumbnailService
    
    // MARK: - Project/Timeline Services
    
    let projectFileManager: ProjectFileManager
    let timelineEngine: TimelineEngine
    let cursorTrackingService: CursorTrackingService
    let clickTrackingService: ClickTrackingService
    let timelineThumbnailService: ThumbnailService
    let renderingService: RenderingService
    
    // MARK: - Utility Services
    
    let logManager: LogManager
    let apiKeyManager: APIKeyManager
    let keychainService: KeychainService
    let featureDiscovery: FeatureDiscovery
    let memoryManager: MemoryManager
    let stressTestRunner: StressTestRunner
    let globalHotkeyManager: GlobalHotkeyManager
    let crashReporter: CrashReporter
    let debugVerifier: DebugVerifier
    let logExportService: LogExportService
    let audioEnhancementService: SaneAudioEnhancementService
    
    // MARK: - Diagnostics Services
    
    let performanceMetrics: PerformanceMetricsService
    let systemHealth: SystemHealthService
    let exportSpeedTracker: ExportSpeedTracker
    
    // MARK: - Configuration
    
    let pricingConfiguration: PricingConfiguration
    
    // Main-actor isolated lazy properties - must be accessed from main thread
    lazy var appState: AppState = AppState()
    lazy var userPreferences: UserPreferences = UserPreferences()

    // MARK: - Initialization

    private init() {
        // Core Services
        self.cameraService = CameraManager()
        self.projectStore = ProjectStore()
        self.exportService = ExportEngine()

        self.thumbnailService = ThumbnailGeneratorService()
        self.silenceDetector = SilenceDetector()
        self.permissionManager = PermissionManager()
        self.audioService = AudioService(permissionManager: self.permissionManager)
        
        // UI Services
        self.toastManager = ToastManager()
        self.hapticsManager = HapticsManager()
        self.soundManager = SoundManager()
        self.errorPresenter = ErrorPresenter()
        
        // Export Services
        self.youtubeService = YouTubeService()
        self.pdfService = PDFGeneratorService()
        self.ffmpegService = FFmpegService()
        self.shareLinkService = ShareLinkService()
        
        // Audio/Voice Services
        self.voiceoverService = VoiceoverService()
        self.waveformService = WaveformService()
        self.soundAnalysisService = SoundAnalysisService()
        self.voiceIsolationService = VoiceIsolationService()
        
        // AI/ML Services
        self.aiService = AIService()
        self.appleSpeechService = AppleSpeechService()
        self.smartFillerDetector = SmartFillerDetector()
        self.sentimentAnalysisService = SentimentAnalysisService()
        
        self.visionOrchestrator = VisionOrchestrator()
        
        // Project/Timeline Services
        self.projectFileManager = ProjectFileManager()
        self.timelineEngine = TimelineEngine()
        self.cursorTrackingService = CursorTrackingService()
        self.clickTrackingService = ClickTrackingService()
        self.timelineThumbnailService = ThumbnailService()
        
        let renderingService = RenderingService.shared
        self.renderingService = renderingService
        
        // Vision Services (Now using unified context)
        self.bodyPoseService = BodyPoseService()
        self.faceTrackingService = FaceTrackingService()
        self.personSegmentationService = PersonSegmentationService(ciContext: renderingService.ciContext)
        self.saliencyService = SaliencyService()
        self.textRecognitionService = TextRecognitionService()
        self.generativeVisionService = GenerativeVisionService(ciContext: renderingService.ciContext)
        self.smartThumbnailService = SmartThumbnailService()
        
        // Utility Services  
        self.logManager = LogManager()
        self.apiKeyManager = APIKeyManager()
        self.keychainService = KeychainService()
        self.featureDiscovery = FeatureDiscovery()
        self.memoryManager = MemoryManager()
        self.stressTestRunner = StressTestRunner()
        self.globalHotkeyManager = GlobalHotkeyManager()
        self.crashReporter = CrashReporter()
        self.debugVerifier = DebugVerifier()
        self.logExportService = LogExportService()
        self.audioEnhancementService = SaneAudioEnhancementService()
        
        // Diagnostics Services
        self.performanceMetrics = PerformanceMetricsService()
        self.systemHealth = SystemHealthService()
        self.exportSpeedTracker = ExportSpeedTracker()
        
        // Configuration
        self.pricingConfiguration = PricingConfiguration()
        
        // Warm up critical heavy systems
        Task { await self.visionOrchestrator.warmup() }
    }
}

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

    /// Unified thumbnail service (consolidated from ThumbnailGeneratorService + SmartThumbnailService)
    let thumbnailService: ThumbnailService
    let silenceDetector: SilenceDetector
    var audioService: AudioService
    let permissionManager: PermissionManager
    
    // MARK: - UI Services
    
    let toastManager: ToastManager
    let hapticsManager: HapticsManager
    let soundManager: SoundManager
    let errorPresenter: ErrorPresenter
    
    // MARK: - Export Services
    
    let pdfService: PDFGeneratorService
    let shareLinkService: ShareLinkService
    let updaterService: UpdaterService
    
    // MARK: - Audio/Voice Services
    
    let voiceoverService: VoiceoverService
    let waveformService: WaveformService
    let soundAnalysisService: SoundAnalysisService
    let voiceIsolationService: VoiceIsolationService
    let realTimeAudioProcessor: RealTimeAudioProcessor
    
    // MARK: - AI/ML Services

    let aiService: AIService
    let transcriptionCoordinator: TranscriptionCoordinator
    let smartFillerDetector: SmartFillerDetector
    let mlEffectsService: MLEffectsService
    
    // MARK: - Vision Services
    
    
    @available(macOS 26.0, *)
    var translationService: TranslationService {
        TranslationService.shared
    }
    
    // MARK: - Vision Services
    
    let faceTrackingService: FaceTrackingService
    let personSegmentationService: PersonSegmentationService
    let saliencyService: SaliencyService
    // smartThumbnailService consolidated into thumbnailService
    
    // MARK: - Project/Timeline Services

    let projectFileManager: ProjectFileManager
    let timelineEngine: TimelineEngine
    let clickTrackingService: ClickTrackingService
    // timelineThumbnailService consolidated into thumbnailService
    let renderingService: RenderingService

    // MARK: - Utility Services
    
    let logManager: LogManager
    let featureDiscovery: FeatureDiscovery
    let memoryManager: MemoryManager
    let stressTestRunner: StressTestRunner
    let globalHotkeyManager: GlobalHotkeyManager
    let crashReporter: CrashReporter
    let logExportService: LogExportService
    let audioEnhancementService: SaneAudioEnhancementService
    
    // MARK: - Diagnostics Services

    let performanceMetrics: PerformanceMetricsService
    let systemHealth: SystemHealthService
    let exportSpeedTracker: ExportSpeedTracker
    let recordingBenchmark: RecordingBenchmark
    
    // MARK: - Configuration
    
    let pricingConfiguration: PricingConfiguration
    
    // Main-actor isolated lazy properties - must be accessed from main thread
    lazy var appState: AppState = AppState()
    lazy var userPreferences: UserPreferences = UserPreferences()

    // MARK: - Initialization

    private init() {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Core Services
        self.cameraService = CameraManager()
        self.projectStore = ProjectStore()
        self.exportService = ExportEngine()

        self.thumbnailService = ThumbnailService()
        self.silenceDetector = SilenceDetector()
        self.permissionManager = PermissionManager()
        self.audioService = AudioService(permissionManager: self.permissionManager)
        
        // UI Services
        self.toastManager = ToastManager()
        self.hapticsManager = HapticsManager()
        self.soundManager = SoundManager()
        self.errorPresenter = ErrorPresenter()
        
        // Export Services
        self.pdfService = PDFGeneratorService()
        self.shareLinkService = ShareLinkService()
        self.updaterService = UpdaterService()
        
        // Audio/Voice Services
        self.voiceoverService = VoiceoverService()
        self.waveformService = WaveformService()
        self.soundAnalysisService = SoundAnalysisService()
        self.voiceIsolationService = VoiceIsolationService()
        self.realTimeAudioProcessor = RealTimeAudioProcessor()
        
        // AI/ML Services
        self.aiService = AIService()
        self.transcriptionCoordinator = TranscriptionCoordinator()
        self.smartFillerDetector = SmartFillerDetector()
        self.mlEffectsService = MLEffectsService()

        
        // Project/Timeline Services
        self.projectFileManager = ProjectFileManager()
        self.timelineEngine = TimelineEngine()
        self.clickTrackingService = ClickTrackingService()
        // timelineThumbnailService now consolidated into thumbnailService

        let renderingService = RenderingService.shared
        self.renderingService = renderingService

        // Vision Services (Now using unified context)
        self.faceTrackingService = FaceTrackingService()
        self.personSegmentationService = PersonSegmentationService(ciContext: renderingService.ciContext)
        self.saliencyService = SaliencyService()
        // smartThumbnailService now consolidated into thumbnailService
        
        // Utility Services  
        self.logManager = LogManager()
        self.featureDiscovery = FeatureDiscovery()
        self.memoryManager = MemoryManager()
        self.stressTestRunner = StressTestRunner()
        self.globalHotkeyManager = GlobalHotkeyManager()
        self.crashReporter = CrashReporter()
        self.logExportService = LogExportService()
        self.audioEnhancementService = SaneAudioEnhancementService()
        
        // Diagnostics Services
        self.performanceMetrics = PerformanceMetricsService()
        self.systemHealth = SystemHealthService()
        self.exportSpeedTracker = ExportSpeedTracker()
        self.recordingBenchmark = RecordingBenchmark()
        
        // Configuration
        self.pricingConfiguration = PricingConfiguration()
        
        // Log initialization time
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0.1 {
            AppLogger.general.warning("⚠️ ServiceContainer init took \(String(format: "%.3f", elapsed))s - consider lazy loading")
        } else {
            AppLogger.general.info("✅ ServiceContainer init completed in \(String(format: "%.3f", elapsed))s")
        }
    }
}

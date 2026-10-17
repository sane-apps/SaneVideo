import AVFoundation
import Foundation

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
    
    // MARK: - Project/Timeline Services

    let projectFileManager: ProjectFileManager
    let timelineEngine: TimelineEngine
    let clickTrackingService: ClickTrackingService
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

        self.cameraService = CameraManager()
        self.projectStore = ProjectStore()
        self.exportService = ExportEngine()

        self.thumbnailService = ThumbnailService()
        self.silenceDetector = SilenceDetector()
        self.permissionManager = PermissionManager()
        self.audioService = AudioService(permissionManager: self.permissionManager)
        
        self.toastManager = ToastManager()
        self.hapticsManager = HapticsManager()
        self.soundManager = SoundManager()
        self.errorPresenter = ErrorPresenter()
        
        self.pdfService = PDFGeneratorService()
        self.shareLinkService = ShareLinkService()
        self.updaterService = UpdaterService()
        
        self.voiceoverService = VoiceoverService()
        self.waveformService = WaveformService()
        self.soundAnalysisService = SoundAnalysisService()
        self.voiceIsolationService = VoiceIsolationService()
        self.realTimeAudioProcessor = RealTimeAudioProcessor()
        
        self.aiService = AIService()
        self.transcriptionCoordinator = TranscriptionCoordinator()
        self.smartFillerDetector = SmartFillerDetector()
        self.mlEffectsService = MLEffectsService()

        
        self.projectFileManager = ProjectFileManager()
        self.timelineEngine = TimelineEngine()
        self.clickTrackingService = ClickTrackingService()

        let renderingService = RenderingService.shared
        self.renderingService = renderingService

        self.faceTrackingService = FaceTrackingService()
        self.personSegmentationService = PersonSegmentationService(ciContext: renderingService.ciContext)
        self.saliencyService = SaliencyService()
        
        self.logManager = LogManager()
        self.featureDiscovery = FeatureDiscovery()
        self.memoryManager = MemoryManager()
        self.stressTestRunner = StressTestRunner()
        self.globalHotkeyManager = GlobalHotkeyManager()
        self.crashReporter = CrashReporter()
        self.logExportService = LogExportService()
        self.audioEnhancementService = SaneAudioEnhancementService()
        
        self.performanceMetrics = PerformanceMetricsService()
        self.systemHealth = SystemHealthService()
        self.exportSpeedTracker = ExportSpeedTracker()
        self.recordingBenchmark = RecordingBenchmark()
        
        self.pricingConfiguration = PricingConfiguration()
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0.1 {
            AppLogger.general.warning("⚠️ ServiceContainer init took \(String(format: "%.3f", elapsed))s - consider lazy loading")
        } else {
            AppLogger.general.info("✅ ServiceContainer init completed in \(String(format: "%.3f", elapsed))s")
        }
    }
}

import Foundation
import Translation
import OSLog

@available(macOS 26.0, *)
actor TranslationService {
    static let shared = TranslationService()
    
    private let logger = Logger(subsystem: "com.sanevideo.SaneVideo", category: "Translation")
    
    private init() {}
    
    /// Translates text using the on-device Translation framework
    func translate(_ text: String, from sourceLanguage: String? = nil, to targetLanguage: String) async throws -> String {
        logger.info("Translating text to \(targetLanguage)")

        let targetLanguage = Locale.Language(identifier: targetLanguage)
        let sourceLanguage = sourceLanguage.map { Locale.Language(identifier: $0) }

#if compiler(>=6.2)
        // Without a source language, assume en-US.

        let availability = LanguageAvailability()
        let source = sourceLanguage ?? Locale.Language(identifier: "en-US")
        let status = await availability.status(from: source, to: targetLanguage)

        guard status == .installed || status == .supported else {
            logger.error("Translation for this language pair is not supported")
            throw TranslationError.unsupportedLanguagePairing
        }

        // init(installedSource:target:) needs macOS 26.0+.
        let session = TranslationSession(installedSource: source, target: targetLanguage)
        let response = try await session.translate(text)

        return response.targetText
#else
        logger.error("TranslationSession direct initialization requires a newer compiler toolchain")
        throw TranslationError.unsupportedLanguagePairing
#endif
    }
}

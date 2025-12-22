import Danger
import Foundation

let danger = Danger()

// MARK: - File Line Count Guard (SOP Compliance)
let MAX_LINES = 500
let swiftFiles = danger.git.createdFiles + danger.git.modifiedFiles
    .filter { $0.hasSuffix(".swift") }

for file in swiftFiles {
    let content = danger.utils.readFile(file)
    let lineCount = content.components(separatedBy: .newlines).count
    
    if lineCount > MAX_LINES {
        danger.fail("📏 SOP Violation: [\(file)](file:///\(file)) is too large (\(lineCount) lines). Please refactor into extensions (Max: \(MAX_LINES) lines).")
    }
}

// MARK: - Singleton Check (Excluding blessed ones)
let forbiddenSingletons = swiftFiles.filter { file in
    let content = danger.utils.readFile(file)
    let isExempt = file.contains("ServiceContainer.swift") || 
                   file.contains("RenderingService.swift") || 
                   file.contains("HealthCheckTool.swift")
    
    return !isExempt && (content.contains("static let shared") || content.contains("static var shared"))
}

for file in forbiddenSingletons {
    danger.warn("⚠️ Singleton Pattern detected in [\(file)](file:///\(file)). Please use Initializer Injection via the `ServiceContainer` instead.")
}

// MARK: - SwiftLint Integration
// This assumes 'swiftlint' is installed on the CI runner
SwiftLint.lint(danger: danger, lintAllFiles: false)

// MARK: - PR Hygiene
let prTitle = danger.github.pullRequest.title
if prTitle.contains("WIP") || prTitle.contains("Draft") {
    danger.warn("PR is still in progress (Draft/WIP).")
}

if danger.github.pullRequest.body?.count ?? 0 < 10 {
    danger.warn("Please provide a more detailed PR description.")
}

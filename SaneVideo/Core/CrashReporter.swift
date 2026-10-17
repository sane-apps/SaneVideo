import Foundation
import MetricKit

/// MetricKit only delivers reports from users who opt in to sharing diagnostics.
@MainActor
@Observable
final class CrashReporter: NSObject {

    private(set) var lastCrashDate: Date?
    private(set) var crashCount: Int = 0

    override init() {
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
        AppLogger.general.info("📊 CrashReporter: MetricKit subscription activated")
    }

}

extension CrashReporter: MXMetricManagerSubscriber {
#if swift(>=6.2)
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let cpu = payload.cpuMetrics {
                let time = cpu.cumulativeCPUTime.converted(to: .seconds).value
                let formatted = String(format: "%.2f", time)
                Task { @MainActor in
                    AppLogger.general.info("📊 MetricKit: CPU \(formatted)s")
                }
            }
            if let mem = payload.memoryMetrics {
                let peak = mem.peakMemoryUsage.converted(to: .megabytes).value
                let formatted = String(format: "%.1f", peak)
                Task { @MainActor in
                    AppLogger.general.info("📊 MetricKit: Peak memory \(formatted)MB")
                }
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let crashes = payload.crashDiagnostics {
                for crash in crashes {
                    let type = crash.exceptionType?.intValue ?? -1
                    let code = crash.exceptionCode?.intValue ?? -1
                    Task { @MainActor in
                        self.crashCount += 1
                        self.lastCrashDate = Date()
                        AppLogger.general.fault("💥 CRASH: type=\(type), code=\(code)")
                    }
                }
            }
            if let hangs = payload.hangDiagnostics {
                for hang in hangs {
                    let duration = hang.hangDuration.converted(to: .seconds).value
                    let formatted = String(format: "%.2f", duration)
                    Task { @MainActor in
                        AppLogger.general.warning("🕐 HANG: \(formatted)s")
                    }
                }
            }
        }
    }
#endif
}

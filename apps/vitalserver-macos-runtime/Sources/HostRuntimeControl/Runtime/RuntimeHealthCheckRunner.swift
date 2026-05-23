import RuntimeCore
import RuntimeContracts

struct RuntimeHealthCheckRunner {
    var printStatus: () throws -> Void
    var healthSnapshot: () -> RuntimeHealthSnapshot
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var reasonText: ([RuntimeFailureReason]) -> String
    var printLine: (String) -> Void

    func run() throws {
        try printStatus()
        let snapshot = healthSnapshot()

        guard snapshot.isHealthy else {
            let reasons = reasonText(snapshot.failureReasons)
            try? writeStatus(.degraded, .health, "runtime health check failed: \(reasons)")
            printLine("health: failed")
            throw LauncherError.runtimeHealthFailed
        }

        try writeStatus(.healthy, .health, "runtime health check passed")
        printLine("health: ok")
    }
}

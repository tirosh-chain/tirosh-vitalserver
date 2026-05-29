import Core
import Contracts

struct RuntimeHealthCheckRunner {
    var printStatus: () throws -> Void
    var healthSnapshot: () -> RuntimeHealthSnapshot
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var recordObservedEvent: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) throws -> Void
    var reasonText: ([RuntimeFailureReason]) -> String
    var printLine: (String) -> Void

    func run() throws {
        try printStatus()
        let snapshot = healthSnapshot()

        guard RuntimeHealthSnapshotPolicy.isHealthy(snapshot) else {
            let reasons = reasonText(snapshot.failureReasons)
            try? writeStatus(.degraded, .health, "runtime health check failed: \(reasons)")
            try? recordObservedEvent(
                .degraded,
                .health,
                "\(observedErrorLabel(snapshot)) observed: \(observedErrorText(snapshot))",
                snapshot
            )
            printLine("health: failed")
            throw LauncherError.runtimeHealthFailed
        }

        try writeStatus(.healthy, .health, "runtime health check passed")
        printLine("health: ok")
    }

    private func observedErrorLabel(_ snapshot: RuntimeHealthSnapshot) -> String {
        snapshot.vmErrors.isEmpty ? "runtime domain errors" : "runtime VM errors"
    }

    private func observedErrorText(_ snapshot: RuntimeHealthSnapshot) -> String {
        let vmErrors = snapshot.vmErrors.map(\.rawValue)
        if !vmErrors.isEmpty {
            return vmErrors.joined(separator: ", ")
        }
        return reasonText(snapshot.failureReasons)
    }
}

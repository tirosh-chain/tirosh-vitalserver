import Core
import Contracts

struct RuntimeHealthCheckRunner {
    var printStatus: () throws -> Void
    var healthSnapshot: () -> RuntimeHealthSnapshot
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var recordObservedEvent: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) throws -> Void
    var reasonText: ([RuntimeFailureReason]) -> String
    var log: (String) -> Void
    var printLine: (String) -> Void

    func run() throws {
        try printStatus()
        let snapshot = healthSnapshot()

        guard RuntimeHealthSnapshotPolicy.isHealthy(snapshot) else {
            let reasons = reasonText(snapshot.failureReasons)
            writeRuntimeStatusBestEffort(
                .degraded,
                operation: .health,
                message: "runtime health check failed: \(reasons)",
                writeStatus: writeStatus,
                log: log
            )
            recordRuntimeObservedEventBestEffort(
                .degraded,
                operation: .health,
                message: "\(observedErrorLabel(snapshot)) observed: \(observedErrorText(snapshot))",
                snapshot: snapshot,
                recordObservedEvent: recordObservedEvent,
                log: log
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

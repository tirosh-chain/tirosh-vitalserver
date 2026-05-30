import Core
import Contracts

struct RuntimeWorkflowStatusReporter {
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    var log: (String) -> Void

    func write(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String
    ) throws {
        try writeStatus(status, operation, message)
    }

    func writeBestEffort(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String
    ) {
        writeRuntimeStatusBestEffort(
            status,
            operation: operation,
            message: message,
            writeStatus: writeStatus,
            log: log
        )
    }

    func publishProgress(_ event: RuntimeStepExecutionEvent) {
        log("step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)")
        writeRuntimeProgressBestEffort(event, writeProgress: writeProgress, log: log)
    }
}

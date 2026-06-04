import Contracts
import Core

func writeRuntimeStatusBestEffort(
    _ status: RuntimeStatusLevel,
    operation: RuntimeOperation,
    message: String,
    writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
    log: (String) -> Void
) {
    do {
        try writeStatus(status, operation, message)
    } catch {
        log(
            "failed to write runtime status " +
                "status=\(status.rawValue) operation=\(operation.rawValue) error=\(error)"
        )
    }
}

func writeRuntimeProgressBestEffort(
    _ event: RuntimeStepExecutionEvent,
    writeProgress: (RuntimeStepExecutionEvent) throws -> Void,
    log: (String) -> Void
) {
    do {
        try writeProgress(event)
    } catch {
        log(
            "failed to write runtime progress " +
                "step=\(event.step.rawValue) stepStatus=\(event.stepStatus.rawValue) error=\(error)"
        )
    }
}

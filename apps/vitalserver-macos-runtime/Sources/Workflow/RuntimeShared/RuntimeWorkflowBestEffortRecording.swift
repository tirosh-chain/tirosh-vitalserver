import Contracts
import Application

public func writeRuntimeStatusBestEffort(
    _ status: RuntimeStatusLevel,
    operation: RuntimeOperation,
    message: String,
    writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
    describeError: (Error) -> String,
    log: (String) -> Void
) {
    do {
        try writeStatus(status, operation, message)
    } catch {
        log(RuntimeWorkflowUseCase().statusWriteFailedLogMessage(
            status: status,
            operation: operation,
            reason: describeError(error)
        )
        )
    }
}

public func writeRuntimeProgressBestEffort(
    _ event: RuntimeStepExecutionEvent,
    writeProgress: (RuntimeStepExecutionEvent) throws -> Void,
    describeError: (Error) -> String,
    log: (String) -> Void
) {
    do {
        try writeProgress(event)
    } catch {
        log(RuntimeWorkflowUseCase().progressWriteFailedLogMessage(
            event: event,
            reason: describeError(error)
        )
        )
    }
}

public func recordRuntimeObservedEventBestEffort(
    _ status: RuntimeStatusLevel,
    operation: RuntimeOperation,
    message: String,
    snapshot: RuntimeHealthSnapshot,
    recordObservedEvent: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) throws -> Void,
    describeError: (Error) -> String,
    log: (String) -> Void
) {
    do {
        try recordObservedEvent(status, operation, message, snapshot)
    } catch {
        log(RuntimeWorkflowUseCase().observedEventRecordFailedLogMessage(
            status: status,
            operation: operation,
            reason: describeError(error)
        )
        )
    }
}

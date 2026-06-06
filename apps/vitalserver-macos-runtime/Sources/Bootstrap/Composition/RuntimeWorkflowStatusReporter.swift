import Contracts
import Errors
import Application

public struct RuntimeWorkflowStatusReporter {
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    public var log: (String) -> Void

    public init(
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
        self.log = log
    }

    public func write(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String
    ) throws {
        try writeStatus(status, operation, message)
    }

    public func writeBestEffort(
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

    public func publishProgress(_ event: RuntimeStepExecutionEvent) {
        log(RuntimeWorkflowUseCase().progressLogMessage(event: event))
        writeRuntimeProgressBestEffort(event, writeProgress: writeProgress, log: log)
    }
}

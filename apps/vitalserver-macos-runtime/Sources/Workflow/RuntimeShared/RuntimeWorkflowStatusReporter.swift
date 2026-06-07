import Contracts
import Application

public struct RuntimeWorkflowStatusReporter {
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var writeProgress: (RuntimeStepExecutionEvent) throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeProgress: @escaping (RuntimeStepExecutionEvent) throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.writeStatus = writeStatus
        self.writeProgress = writeProgress
        self.describeError = describeError
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
            describeError: describeError,
            log: log
        )
    }

    public func publishProgress(_ event: RuntimeStepExecutionEvent) {
        log(RuntimeOperationReportingUseCase().progressLogMessage(event: event))
        writeRuntimeProgressBestEffort(
            event,
            writeProgress: writeProgress,
            describeError: describeError,
            log: log
        )
    }
}

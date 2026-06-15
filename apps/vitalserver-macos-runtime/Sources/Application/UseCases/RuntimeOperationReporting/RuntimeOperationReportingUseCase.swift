import Contracts
import Foundation
import Errors

public struct RuntimeOperationReportingUseCase {
    public init() {}

    public func progressLogMessage(event: RuntimeStepExecutionEvent) -> String {
        "step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)"
    }

    public func statusWriteFailedLogMessage(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        reason: String
    ) -> String {
        "failed to write runtime status status=\(status.rawValue) operation=\(operation.rawValue) error=\(reason)"
    }

    public func progressWriteFailedLogMessage(
        event: RuntimeStepExecutionEvent,
        reason: String
    ) -> String {
        "failed to write runtime progress step=\(event.step.rawValue) stepStatus=\(event.stepStatus.rawValue) error=\(reason)"
    }

    public func observedEventRecordFailedLogMessage(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        reason: String
    ) -> String {
        "failed to record runtime observed event status=\(status.rawValue) operation=\(operation.rawValue) error=\(reason)"
    }
}

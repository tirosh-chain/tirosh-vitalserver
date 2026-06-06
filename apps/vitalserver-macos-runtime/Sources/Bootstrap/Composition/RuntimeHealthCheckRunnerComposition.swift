import Contracts
import Foundation
import InboundAdapters
import Errors

public struct RuntimeHealthCheckRunnerCompositionOperations {
    let printStatus: () throws -> Void
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let recordObservedEvent: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) throws -> Void
    let log: (String) -> Void
    let printLine: (String) -> Void

    public init(
        printStatus: @escaping () throws -> Void,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        recordObservedEvent: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot,
            RuntimeEventType
        ) throws -> Void,
        log: @escaping (String) -> Void,
        printLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.printStatus = printStatus
        self.healthSnapshot = healthSnapshot
        self.writeStatus = writeStatus
        self.recordObservedEvent = recordObservedEvent
        self.log = log
        self.printLine = printLine
    }
}

public enum RuntimeHealthCheckRunnerComposition {
    public static func make(
        operations: RuntimeHealthCheckRunnerCompositionOperations
    ) -> RuntimeHealthCheckRunner {
        RuntimeHealthCheckRunner(
            printStatus: operations.printStatus,
            healthSnapshot: operations.healthSnapshot,
            writeStatus: operations.writeStatus,
            writeStatusBestEffort: { status, operation, message in
                writeRuntimeStatusBestEffort(
                    status,
                    operation: operation,
                    message: message,
                    writeStatus: operations.writeStatus,
                    log: operations.log
                )
            },
            recordObservedEventBestEffort: { status, operation, message, snapshot in
                recordRuntimeObservedEventBestEffort(
                    status,
                    operation: operation,
                    message: message,
                    snapshot: snapshot,
                    recordObservedEvent: { status, operation, message, snapshot in
                        try operations.recordObservedEvent(
                            status,
                            operation,
                            message,
                            snapshot,
                            .healthObserved
                        )
                    },
                    log: operations.log
                )
            },
            printLine: operations.printLine
        )
    }
}

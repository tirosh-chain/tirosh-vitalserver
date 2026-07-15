import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import Workflow
import Errors

public struct RuntimeHealthWaitRunnerCompositionOperations {
    let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let now: () -> Date
    let sleep: (TimeInterval) -> Void
    let log: (String) -> Void

    public init(
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        now: @escaping () -> Date,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.serviceState = serviceState
        self.healthSnapshot = healthSnapshot
        self.writeStatus = writeStatus
        self.now = now
        self.sleep = sleep
        self.log = log
    }
}

public enum RuntimeHealthWaitRunnerComposition {
    public static func make(
        operations: RuntimeHealthWaitRunnerCompositionOperations
    ) -> RuntimeHealthWaitRunner {
        RuntimeHealthWaitRunner(
            context: RuntimeHealthWaitWorkflowContext(
                timeoutSeconds: Constants.Runtime.waitTimeoutSeconds,
                pollIntervalSeconds: 3.0,
                progressEveryAttempts: 5
            ),
            serviceStates: { services in
                Dictionary(uniqueKeysWithValues: services.map { service in
                    (service, operations.serviceState(service))
                })
            },
            healthSnapshot: operations.healthSnapshot,
            writeStatusBestEffort: { status, operation, message in
                writeRuntimeStatusBestEffort(
                    status,
                    operation: operation,
                    message: message,
                    writeStatus: operations.writeStatus,
                    describeError: RuntimeErrorDescription.describe,
                    log: operations.log
                )
            },
            now: operations.now,
            sleep: operations.sleep,
            log: operations.log
        )
    }
}

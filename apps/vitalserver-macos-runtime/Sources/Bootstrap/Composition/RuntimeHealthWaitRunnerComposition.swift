import Contracts
import Domain
import Foundation
import Interfaces
import Workflow

public struct RuntimeHealthWaitRunnerCompositionOperations {
    let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let sleep: (TimeInterval) -> Void
    let log: (String) -> Void

    public init(
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.serviceState = serviceState
        self.healthSnapshot = healthSnapshot
        self.writeStatus = writeStatus
        self.sleep = sleep
        self.log = log
    }
}

public enum RuntimeHealthWaitRunnerComposition {
    public static func make(
        operations: RuntimeHealthWaitRunnerCompositionOperations
    ) -> RuntimeHealthWaitRunner {
        RuntimeHealthWaitRunner(
            configuration: RuntimeHealthWaitWorkflowConfiguration(
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
                    log: operations.log
                )
            },
            sleep: {
                operations.sleep(3)
            },
            log: operations.log
        )
    }
}

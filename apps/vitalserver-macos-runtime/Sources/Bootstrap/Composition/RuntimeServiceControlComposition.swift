import Contracts
import Domain
import Foundation
import Interfaces

public struct RuntimeServiceControlCompositionOperations {
    let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    let stopRuntimeServices: () throws -> Void
    let launchdState: (RuntimeManagedService) -> RuntimeServiceState
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let log: (String) -> Void

    public init(
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        launchdState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.startRuntimeServices = startRuntimeServices
        self.stopRuntimeServices = stopRuntimeServices
        self.launchdState = launchdState
        self.writeStatus = writeStatus
        self.log = log
    }
}

public enum RuntimeServiceControlComposition {
    public static func make(
        operations: RuntimeServiceControlCompositionOperations
    ) -> RuntimeServiceControlRunner {
        RuntimeServiceControlRunner(
            startRuntimeServices: operations.startRuntimeServices,
            stopRuntimeServices: operations.stopRuntimeServices,
            serviceStates: { services in
                Dictionary(uniqueKeysWithValues: services.map { service in
                    (service, operations.launchdState(service))
                })
            },
            writeStatus: operations.writeStatus,
            log: operations.log
        )
    }
}

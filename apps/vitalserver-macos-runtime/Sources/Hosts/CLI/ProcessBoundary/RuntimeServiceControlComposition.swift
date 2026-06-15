import Application
import Contracts
import Domain
import Foundation
import InboundAdapters
import Errors

public struct RuntimeServiceControlCompositionOperations {
    let startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    let stopRuntimeServices: () throws -> Void
    let launchdState: (RuntimeManagedService) -> RuntimeServiceState
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let log: (String) -> Void

    public init(
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void,
        launchdState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.startRuntimeServices = startRuntimeServices
        self.stopRuntimeServices = stopRuntimeServices
        self.launchdState = launchdState
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.log = log
    }
}

public enum RuntimeServiceControlComposition {
    public static func make(
        operations: RuntimeServiceControlCompositionOperations
    ) -> RuntimeServiceControlRunner {
        let vmStateControl = RuntimeVMStateControlUseCase()
        let vmStateOperations = RuntimeVMServiceControlOperations(
            startRuntimeServices: operations.startRuntimeServices,
            stopRuntimeServices: operations.stopRuntimeServices
        )
        return RuntimeServiceControlRunner(
            useCase: ControlRuntimeServicesUseCase(),
            startRuntimeServices: { policy in
                try vmStateControl.startRuntimeServicesForServiceControl(
                    policy,
                    operations: vmStateOperations
                )
            },
            stopRuntimeServices: {
                try vmStateControl.stopRuntimeServicesForServiceControl(
                    operations: vmStateOperations
                )
            },
            serviceStates: { services in
                Dictionary(uniqueKeysWithValues: services.map { service in
                    (service, operations.launchdState(service))
                })
            },
            waitForHealth: operations.waitForHealth,
            writeStatus: operations.writeStatus,
            log: operations.log
        )
    }
}

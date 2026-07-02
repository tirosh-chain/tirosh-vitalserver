import Application
import Bootstrap
import Contracts
import Domain
import Errors
import Foundation
import Workflow

public struct RuntimeDatastoreRepairCompositionContext {
    public init() {}
}

public struct RuntimeDatastoreRepairCompositionOperations {
    let isVMServiceLoaded: () -> Bool
    let startVMService: () throws -> Void
    let runGuestDatastoreRepair: () throws -> RuntimeGuestControlServiceOperation
    let restartProxyService: () throws -> Void
    let restartWatchdogService: () throws -> Void
    let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let log: (String) -> Void

    public init(
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        runGuestDatastoreRepair: @escaping () throws -> RuntimeGuestControlServiceOperation,
        restartProxyService: @escaping () throws -> Void,
        restartWatchdogService: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.runGuestDatastoreRepair = runGuestDatastoreRepair
        self.restartProxyService = restartProxyService
        self.restartWatchdogService = restartWatchdogService
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.log = log
    }
}

public struct RuntimeDatastoreRepairComposition {
    let context: RuntimeDatastoreRepairCompositionContext
    let operations: RuntimeDatastoreRepairCompositionOperations

    public init(
        context: RuntimeDatastoreRepairCompositionContext,
        operations: RuntimeDatastoreRepairCompositionOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func repair() throws {
        try RuntimeDatastoreRepairWorkflow().repair(
            context: RunDatastoreRepairContext(),
            operations: RunDatastoreRepairOperations(
                isVMServiceLoaded: operations.isVMServiceLoaded,
                startVMService: operations.startVMService,
                runGuestDatastoreRepair: operations.runGuestDatastoreRepair,
                restartProxyService: operations.restartProxyService,
                restartWatchdogService: operations.restartWatchdogService,
                waitForHealth: operations.waitForHealth,
                writeStatus: operations.writeStatus,
                log: operations.log
            )
        )
    }
}

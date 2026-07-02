import Foundation
import Application
import Contracts
import Domain
import Errors

public struct RunDatastoreRepairContext: Equatable, Sendable {
    public init() {}
}

public struct RunDatastoreRepairOperations {
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let runGuestDatastoreRepair: () throws -> RuntimeGuestControlServiceOperation
    public let restartProxyService: () throws -> Void
    public let restartWatchdogService: () throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let log: (String) -> Void

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

public struct RuntimeDatastoreRepairWorkflow {
    public init() {}

    public func repair(
        context: RunDatastoreRepairContext,
        operations: RunDatastoreRepairOperations
    ) throws {
        let useCase = RuntimeDatastoreRepairUseCase()
        let plan = useCase.plan()
        operations.log(plan.requestedLogMessage)
        try operations.writeStatus(.recovering, .repairDatastore, plan.requestedStatusMessage)

        if !operations.isVMServiceLoaded() {
            try operations.startVMService()
        }

        let operation = try operations.runGuestDatastoreRepair()
        operations.log("datastore repair guest operation completed operationId=\(operation.operationId)")
        try operations.restartProxyService()
        try operations.restartWatchdogService()
        try operations.waitForHealth(plan.restartPolicy)
        try operations.writeStatus(.healthy, .repairDatastore, plan.completedStatusMessage)
        operations.log(plan.completedLogMessage)
    }
}

import Foundation
import Contracts
import Domain

public struct RunDatastoreRepairContext: Equatable, Sendable {
    public let guestRunDirectory: URL
    public let waitTimeoutSeconds: Double

    public init(
        guestRunDirectory: URL,
        waitTimeoutSeconds: Double
    ) {
        self.guestRunDirectory = guestRunDirectory
        self.waitTimeoutSeconds = waitTimeoutSeconds
    }
}

public struct RunDatastoreRepairOperations {
    public let requireCapability: () throws -> Void
    public let createDirectory: (URL, Bool) throws -> Void
    public let removePreviousResult: () throws -> Void
    public let writeRequest: (RuntimeDatastoreRepairRequest) throws -> Void
    public let isVMServiceLoaded: () -> Bool
    public let startVMService: () throws -> Void
    public let restartVMService: () throws -> Void
    public let loadResult: () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
    public let restartProxyService: () throws -> Void
    public let restartWatchdogService: () throws -> Void
    public let waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let writeStatusBestEffort: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public let requestID: () -> String
    public let timestamp: () -> String
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removePreviousResult: @escaping () throws -> Void,
        writeRequest: @escaping (RuntimeDatastoreRepairRequest) throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        restartVMService: @escaping () throws -> Void,
        loadResult: @escaping () -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>,
        restartProxyService: @escaping () throws -> Void,
        restartWatchdogService: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        requestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.createDirectory = createDirectory
        self.removePreviousResult = removePreviousResult
        self.writeRequest = writeRequest
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.restartVMService = restartVMService
        self.loadResult = loadResult
        self.restartProxyService = restartProxyService
        self.restartWatchdogService = restartWatchdogService
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.writeStatusBestEffort = writeStatusBestEffort
        self.requestID = requestID
        self.timestamp = timestamp
        self.sleep = sleep
        self.log = log
    }
}

public struct RunDatastoreRepairUseCase {
    public init() {}

    public func repair(
        context: RunDatastoreRepairContext,
        operations: RunDatastoreRepairOperations
    ) throws {
        let useCase = RepairRuntimeUseCase()
        let plan = useCase.datastoreRepairPlan()
        operations.log(plan.requestedLogMessage)
        try operations.requireCapability()
        try operations.createDirectory(context.guestRunDirectory, true)
        try operations.removePreviousResult()
        try operations.writeStatus(.recovering, .repairDatastore, plan.requestedStatusMessage)

        let request = useCase.datastoreRepairRequest(
            requestID: operations.requestID(),
            requestedAt: operations.timestamp()
        )
        try operations.writeRequest(request)

        if operations.isVMServiceLoaded() {
            try operations.restartVMService()
        } else {
            try operations.startVMService()
        }

        try useCase.waitForDatastoreRepairResult(
            request: request,
            context: DatastoreRepairWaitExecutionContext(
                waitTimeoutSeconds: context.waitTimeoutSeconds,
                pollIntervalSeconds: 3.0,
                progressEveryAttempts: 5
            ),
            operations: DatastoreRepairWaitOperations(
                loadResult: operations.loadResult,
                writeStatusBestEffort: operations.writeStatusBestEffort,
                sleep: operations.sleep,
                log: operations.log
            )
        )
        try operations.restartProxyService()
        try operations.restartWatchdogService()
        try operations.waitForHealth(plan.restartPolicy)
        try operations.writeStatus(.healthy, .repairDatastore, plan.completedStatusMessage)
        operations.log(plan.completedLogMessage)
    }
}

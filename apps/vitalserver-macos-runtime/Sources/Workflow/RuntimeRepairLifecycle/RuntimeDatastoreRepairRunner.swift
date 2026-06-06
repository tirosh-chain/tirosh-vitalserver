import Application
import Contracts
import Domain
import Errors

public struct RuntimeDatastoreRepairRunner {
    public var requireCapability: () throws -> Void
    public var prepareGuestRunDirectory: () throws -> Void
    public var removePreviousResult: () throws -> Void
    public var writeRequest: (RuntimeDatastoreRepairRequest) throws -> Void
    public var isVMServiceLoaded: () -> Bool
    public var startVMService: () throws -> Void
    public var restartVMService: () throws -> Void
    public var waitForResult: (RuntimeDatastoreRepairRequest) throws -> Void
    public var restartProxyService: () throws -> Void
    public var restartWatchdogService: () throws -> Void
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var makeRequestID: () -> String
    public var timestamp: () -> String
    public var log: (String) -> Void
    private var useCase: RepairRuntimeUseCase {
        RepairRuntimeUseCase()
    }

    public init(
        requireCapability: @escaping () throws -> Void,
        prepareGuestRunDirectory: @escaping () throws -> Void,
        removePreviousResult: @escaping () throws -> Void,
        writeRequest: @escaping (RuntimeDatastoreRepairRequest) throws -> Void,
        isVMServiceLoaded: @escaping () -> Bool,
        startVMService: @escaping () throws -> Void,
        restartVMService: @escaping () throws -> Void,
        waitForResult: @escaping (RuntimeDatastoreRepairRequest) throws -> Void,
        restartProxyService: @escaping () throws -> Void,
        restartWatchdogService: @escaping () throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        makeRequestID: @escaping () -> String,
        timestamp: @escaping () -> String,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.prepareGuestRunDirectory = prepareGuestRunDirectory
        self.removePreviousResult = removePreviousResult
        self.writeRequest = writeRequest
        self.isVMServiceLoaded = isVMServiceLoaded
        self.startVMService = startVMService
        self.restartVMService = restartVMService
        self.waitForResult = waitForResult
        self.restartProxyService = restartProxyService
        self.restartWatchdogService = restartWatchdogService
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.makeRequestID = makeRequestID
        self.timestamp = timestamp
        self.log = log
    }

    public func run() throws {
        let plan = useCase.datastoreRepairPlan()
        log(plan.requestedLogMessage)
        try requireCapability()
        try prepareGuestRunDirectory()
        try removePreviousResult()
        try writeStatus(.recovering, .repairDatastore, plan.requestedStatusMessage)

        let request = useCase.datastoreRepairRequest(
            requestID: makeRequestID(),
            requestedAt: timestamp()
        )
        try writeRequest(request)

        if isVMServiceLoaded() {
            try restartVMService()
        } else {
            try startVMService()
        }

        try waitForResult(request)
        try restartProxyService()
        try restartWatchdogService()
        try waitForHealth(plan.restartPolicy)
        try writeStatus(.healthy, .repairDatastore, plan.completedStatusMessage)
        log(plan.completedLogMessage)
    }
}

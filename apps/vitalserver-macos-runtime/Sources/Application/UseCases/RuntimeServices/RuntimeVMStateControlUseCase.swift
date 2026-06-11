import Contracts
import Domain
import Foundation

public enum RuntimeVMControlIntent: Equatable, Sendable {
    case restartAfterSettingsApply
    case restartForWatchdogRecovery
    case startForGuestOperation
    case restartForRepairOperation

    public var operation: RuntimeOperation {
        switch self {
        case .restartAfterSettingsApply:
            return .configure
        case .restartForWatchdogRecovery:
            return .watchdog
        case .startForGuestOperation:
            return .health
        case .restartForRepairOperation:
            return .repairDatastore
        }
    }
}

public struct RuntimeVMRestartPlan: Equatable, Sendable {
    public let intent: RuntimeVMControlIntent
    public let operation: RuntimeOperation
    public let requestedStatus: RuntimeStatusLevel
    public let requestedStatusMessage: String
    public let startPolicy: RuntimeServiceRestartPolicy
    public let completionStatus: RuntimeStatusLevel
    public let completionStatusMessage: String

    public init(
        intent: RuntimeVMControlIntent,
        operation: RuntimeOperation,
        requestedStatus: RuntimeStatusLevel,
        requestedStatusMessage: String,
        startPolicy: RuntimeServiceRestartPolicy,
        completionStatus: RuntimeStatusLevel,
        completionStatusMessage: String
    ) {
        self.intent = intent
        self.operation = operation
        self.requestedStatus = requestedStatus
        self.requestedStatusMessage = requestedStatusMessage
        self.startPolicy = startPolicy
        self.completionStatus = completionStatus
        self.completionStatusMessage = completionStatusMessage
    }
}

public struct RuntimeVMStateControlOperations {
    public var runtimeVersion: () throws -> String
    public var runningVMProcessID: () throws -> pid_t
    public var prepareGuestShutdown: (String) throws -> Void
    public var clearGuestShutdownPreparation: () throws -> Void
    public var stopRuntimeServicesAfterGuestPoweroff: (pid_t) throws -> Void
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var log: (String) -> Void

    public init(
        runtimeVersion: @escaping () throws -> String,
        runningVMProcessID: @escaping () throws -> pid_t,
        prepareGuestShutdown: @escaping (String) throws -> Void,
        clearGuestShutdownPreparation: @escaping () throws -> Void,
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.runtimeVersion = runtimeVersion
        self.runningVMProcessID = runningVMProcessID
        self.prepareGuestShutdown = prepareGuestShutdown
        self.clearGuestShutdownPreparation = clearGuestShutdownPreparation
        self.stopRuntimeServicesAfterGuestPoweroff = stopRuntimeServicesAfterGuestPoweroff
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
        self.writeStatus = writeStatus
        self.log = log
    }
}

public struct RuntimeVMRuntimeRestartOperations {
    public var restartVMRuntimeServices: () throws -> Void
    public var forceStopRuntimeServicesAfterGracefulStopFailure: () throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        restartVMRuntimeServices: @escaping () throws -> Void,
        forceStopRuntimeServicesAfterGracefulStopFailure: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.restartVMRuntimeServices = restartVMRuntimeServices
        self.forceStopRuntimeServicesAfterGracefulStopFailure = forceStopRuntimeServicesAfterGracefulStopFailure
        self.describeError = describeError
        self.log = log
    }
}

public struct RuntimeVMServiceControlOperations {
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var stopRuntimeServices: () throws -> Void

    public init(
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        stopRuntimeServices: @escaping () throws -> Void
    ) {
        self.startRuntimeServices = startRuntimeServices
        self.stopRuntimeServices = stopRuntimeServices
    }
}

public struct RuntimeVMSingleServiceOperations {
    public var startVMService: () throws -> Void
    public var restartVMRuntimeServices: () throws -> Void

    public init(
        startVMService: @escaping () throws -> Void,
        restartVMRuntimeServices: @escaping () throws -> Void
    ) {
        self.startVMService = startVMService
        self.restartVMRuntimeServices = restartVMRuntimeServices
    }
}

public struct RuntimeVMUpdateShutdownOperations {
    public var runningVMProcessID: () throws -> pid_t
    public var prepareGuestShutdownForUpdate: (UpdateBundleManifest) throws -> Void
    public var clearGuestShutdownPreparation: () throws -> Void
    public var stopRuntimeServicesAfterGuestPoweroff: (pid_t) throws -> Void
    public var forceStopRuntimeServicesAfterGuestShutdownFailure: () throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        runningVMProcessID: @escaping () throws -> pid_t,
        prepareGuestShutdownForUpdate: @escaping (UpdateBundleManifest) throws -> Void,
        clearGuestShutdownPreparation: @escaping () throws -> Void,
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void,
        forceStopRuntimeServicesAfterGuestShutdownFailure: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.runningVMProcessID = runningVMProcessID
        self.prepareGuestShutdownForUpdate = prepareGuestShutdownForUpdate
        self.clearGuestShutdownPreparation = clearGuestShutdownPreparation
        self.stopRuntimeServicesAfterGuestPoweroff = stopRuntimeServicesAfterGuestPoweroff
        self.forceStopRuntimeServicesAfterGuestShutdownFailure = forceStopRuntimeServicesAfterGuestShutdownFailure
        self.describeError = describeError
        self.log = log
    }
}

public struct RuntimeVMDiskReplacementStopOperations {
    public var stopRuntimeServices: () throws -> Void
    public var forceStopRuntimeServicesAfterGracefulStopFailure: () throws -> Void
    public var describeError: (Error) -> String
    public var log: (String) -> Void

    public init(
        stopRuntimeServices: @escaping () throws -> Void,
        forceStopRuntimeServicesAfterGracefulStopFailure: @escaping () throws -> Void,
        describeError: @escaping (Error) -> String,
        log: @escaping (String) -> Void
    ) {
        self.stopRuntimeServices = stopRuntimeServices
        self.forceStopRuntimeServicesAfterGracefulStopFailure = forceStopRuntimeServicesAfterGracefulStopFailure
        self.describeError = describeError
        self.log = log
    }
}

public enum RuntimeVMStateControlError: Error, Equatable, CustomStringConvertible {
    case unsupportedIntent(String)

    public var description: String {
        switch self {
        case .unsupportedIntent(let intent):
            return "unsupported VM state control intent: \(intent)"
        }
    }
}

public struct RuntimeVMStateControlUseCase {
    public init() {}

    public func restartPlan(intent: RuntimeVMControlIntent) -> RuntimeVMRestartPlan {
        switch intent {
        case .restartAfterSettingsApply:
            return RuntimeVMRestartPlan(
                intent: intent,
                operation: intent.operation,
                requestedStatus: .recovering,
                requestedStatusMessage: "runtime settings applied; preparing guest shutdown before restart",
                startPolicy: RuntimeRequiredServicePolicy.allRuntimeServices,
                completionStatus: .healthy,
                completionStatusMessage: "runtime restarted after settings apply"
            )
        case .restartForWatchdogRecovery:
            return RuntimeVMRestartPlan(
                intent: intent,
                operation: intent.operation,
                requestedStatus: .recovering,
                requestedStatusMessage: "watchdog requested VM runtime restart",
                startPolicy: RuntimeServiceRestartPolicy(
                    restartVM: true,
                    restartGuestLogSync: true,
                    restartProxy: false,
                    restartWatchdog: false
                ),
                completionStatus: .recovering,
                completionStatusMessage: "watchdog dispatched VM runtime restart"
            )
        case .startForGuestOperation:
            return RuntimeVMRestartPlan(
                intent: intent,
                operation: intent.operation,
                requestedStatus: .recovering,
                requestedStatusMessage: "guest operation requested VM service start",
                startPolicy: RuntimeServiceRestartPolicy(
                    restartVM: true,
                    restartGuestLogSync: false,
                    restartProxy: false,
                    restartWatchdog: false
                ),
                completionStatus: .recovering,
                completionStatusMessage: "guest operation started VM service"
            )
        case .restartForRepairOperation:
            return RuntimeVMRestartPlan(
                intent: intent,
                operation: intent.operation,
                requestedStatus: .recovering,
                requestedStatusMessage: "repair operation requested VM runtime restart",
                startPolicy: RuntimeServiceRestartPolicy(
                    restartVM: true,
                    restartGuestLogSync: true,
                    restartProxy: false,
                    restartWatchdog: false
                ),
                completionStatus: .recovering,
                completionStatusMessage: "repair operation restarted VM runtime"
            )
        }
    }

    public func restart(
        intent: RuntimeVMControlIntent,
        operations: RuntimeVMStateControlOperations
    ) throws {
        let plan = restartPlan(intent: intent)
        operations.log(plan.requestedStatusMessage)
        try operations.writeStatus(plan.requestedStatus, plan.operation, plan.requestedStatusMessage)

        let expectedVMProcessID = try operations.runningVMProcessID()
        let version = try operations.runtimeVersion()
        defer {
            do {
                try operations.clearGuestShutdownPreparation()
            } catch {
                operations.log("guest shutdown preparation cleanup failed error=\(error)")
            }
        }

        try operations.prepareGuestShutdown(version)
        try operations.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID)
        try operations.startRuntimeServices(plan.startPolicy)
        try operations.waitForHealth(plan.startPolicy)
        try operations.writeStatus(plan.completionStatus, plan.operation, plan.completionStatusMessage)
        operations.log(plan.completionStatusMessage)
    }

    public func restartVMRuntime(
        intent: RuntimeVMControlIntent,
        operations: RuntimeVMRuntimeRestartOperations
    ) throws {
        guard intent == .restartForWatchdogRecovery else {
            throw RuntimeVMStateControlError.unsupportedIntent("\(intent)")
        }
        let plan = restartPlan(intent: intent)
        operations.log(plan.requestedStatusMessage)
        do {
            try operations.restartVMRuntimeServices()
        } catch {
            guard shouldForceStopAfterVMRuntimeRestartFailure(error) else {
                throw error
            }
            operations.log("watchdog VM runtime restart failed during graceful stop; forcing VM runtime services stop error=\(operations.describeError(error))")
            try operations.forceStopRuntimeServicesAfterGracefulStopFailure()
            try operations.restartVMRuntimeServices()
        }
        operations.log(plan.completionStatusMessage)
    }

    public func startRuntimeServicesForServiceControl(
        _ policy: RuntimeServiceRestartPolicy,
        operations: RuntimeVMServiceControlOperations
    ) throws {
        try startRuntimeServices(policy, operations: operations)
    }

    public func stopRuntimeServicesForServiceControl(
        operations: RuntimeVMServiceControlOperations
    ) throws {
        try stopRuntimeServices(operations: operations)
    }

    public func startRuntimeServices(
        _ policy: RuntimeServiceRestartPolicy,
        operations: RuntimeVMServiceControlOperations
    ) throws {
        try operations.startRuntimeServices(policy)
    }

    public func stopRuntimeServices(
        operations: RuntimeVMServiceControlOperations
    ) throws {
        try operations.stopRuntimeServices()
    }

    public func startVMService(
        intent: RuntimeVMControlIntent,
        operations: RuntimeVMSingleServiceOperations
    ) throws {
        guard intent == .startForGuestOperation else {
            throw RuntimeVMStateControlError.unsupportedIntent("\(intent)")
        }
        try operations.startVMService()
    }

    public func restartVMRuntimeForRepair(
        intent: RuntimeVMControlIntent,
        operations: RuntimeVMSingleServiceOperations
    ) throws {
        guard intent == .restartForRepairOperation else {
            throw RuntimeVMStateControlError.unsupportedIntent("\(intent)")
        }
        try operations.restartVMRuntimeServices()
    }

    public func prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff(
        manifest: UpdateBundleManifest,
        operations: RuntimeVMUpdateShutdownOperations
    ) throws {
        let expectedVMProcessID = try operations.runningVMProcessID()
        operations.log("captured VM process before guest update shutdown pid=\(expectedVMProcessID)")
        defer {
            do {
                try operations.clearGuestShutdownPreparation()
            } catch {
                operations.log("guest shutdown preparation cleanup failed error=\(error)")
            }
        }
        do {
            try operations.prepareGuestShutdownForUpdate(manifest)
            try operations.stopRuntimeServicesAfterGuestPoweroff(expectedVMProcessID)
        } catch {
            guard shouldForceStopAfterUpdateShutdownFailure(error) else {
                throw error
            }
            operations.log("guest update shutdown failed; forcing VM runtime services stop error=\(operations.describeError(error))")
            try operations.forceStopRuntimeServicesAfterGuestShutdownFailure()
            throw error
        }
    }

    public func stopRuntimeServicesForVMDiskReplacement(
        operations: RuntimeVMDiskReplacementStopOperations
    ) throws {
        do {
            try operations.stopRuntimeServices()
            return
        } catch {
            operations.log("graceful runtime services stop failed before VM disk replacement; forcing VM process stop error=\(operations.describeError(error))")
        }

        try operations.forceStopRuntimeServicesAfterGracefulStopFailure()
        operations.log("runtime services stopped for VM disk replacement")
    }

    private func shouldForceStopAfterUpdateShutdownFailure(_ error: Error) -> Bool {
        if error is RuntimeGuestUpdateUseCaseError {
            return true
        }
        if error is StopRuntimeVMProcessUseCaseError {
            return true
        }
        return false
    }

    private func shouldForceStopAfterVMRuntimeRestartFailure(_ error: Error) -> Bool {
        error is StopRuntimeVMProcessUseCaseError
    }
}

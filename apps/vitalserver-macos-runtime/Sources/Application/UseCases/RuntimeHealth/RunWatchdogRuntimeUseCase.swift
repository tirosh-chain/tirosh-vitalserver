import Contracts
import Domain
import Errors
import Foundation

public struct RunWatchdogRuntimeUseCase {
    public init() {}

    public func run(
        operations: RunWatchdogRuntimeOperations,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws {
        let watchdog = WatchdogRuntimeUseCase()

        try operations.prepareLogs()

        if let activeOperation = operations.activeManagedOperation() {
            let plan = watchdog.activeOperationSkipPlan(activeOperation)
            log(plan.logMessage)
            operations.recordLifecycleEvent(.watchdog, plan.lifecycleMessage, plan.eventType)
            printLine(plan.printMessage)
            return
        }

        let initial = operations.healthSnapshot()
        let initialSnapshotResult = try operations.executeInitialSnapshotDecision(
            watchdog.initialSnapshotDecision(initial),
            initial
        )
        if initialSnapshotResult == .handled {
            return
        }

        let proxyLivenessHTTP = operations.proxyLivenessHTTP(initial.proxyPort)
        try operations.executeRecoveryDecision(watchdog.recoveryDecision(
            snapshot: initial,
            hostProxyLivenessHTTP: proxyLivenessHTTP,
            automaticRecoveryEnabled: operations.automaticRecoveryEnabled()
        ), initial)
    }
}

public enum RunWatchdogRuntimeInitialSnapshotExecutionResult: Equatable, Sendable {
    case handled
    case needsRecoveryProbe
}

public struct RunWatchdogRuntimeOperations {
    public let prepareLogs: () throws -> Void
    public let activeManagedOperation: () -> RuntimeOperation?
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let executeInitialSnapshotDecision: (
        WatchdogRuntimeInitialSnapshotDecision,
        RuntimeHealthSnapshot
    ) throws -> RunWatchdogRuntimeInitialSnapshotExecutionResult
    public let proxyLivenessHTTP: (Int) -> String
    public let automaticRecoveryEnabled: () -> Bool
    public let executeRecoveryDecision: (WatchdogRuntimeRecoveryDecision, RuntimeHealthSnapshot) throws -> Void
    public let recordLifecycleEvent: (RuntimeOperation, String, RuntimeEventType) -> Void

    public init(
        prepareLogs: @escaping () throws -> Void,
        activeManagedOperation: @escaping () -> RuntimeOperation?,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        executeInitialSnapshotDecision: @escaping (
            WatchdogRuntimeInitialSnapshotDecision,
            RuntimeHealthSnapshot
        ) throws -> RunWatchdogRuntimeInitialSnapshotExecutionResult,
        proxyLivenessHTTP: @escaping (Int) -> String,
        automaticRecoveryEnabled: @escaping () -> Bool,
        executeRecoveryDecision: @escaping (WatchdogRuntimeRecoveryDecision, RuntimeHealthSnapshot) throws -> Void,
        recordLifecycleEvent: @escaping (RuntimeOperation, String, RuntimeEventType) -> Void
    ) {
        self.prepareLogs = prepareLogs
        self.activeManagedOperation = activeManagedOperation
        self.healthSnapshot = healthSnapshot
        self.executeInitialSnapshotDecision = executeInitialSnapshotDecision
        self.proxyLivenessHTTP = proxyLivenessHTTP
        self.automaticRecoveryEnabled = automaticRecoveryEnabled
        self.executeRecoveryDecision = executeRecoveryDecision
        self.recordLifecycleEvent = recordLifecycleEvent
    }
}

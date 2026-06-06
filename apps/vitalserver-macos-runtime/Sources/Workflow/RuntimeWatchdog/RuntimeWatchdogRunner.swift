import Application
import Contracts
import Foundation
import Errors

public enum RuntimeWatchdogInitialSnapshotExecutionResult: Equatable, Sendable {
    case handled
    case needsRecoveryProbe
}

public struct RuntimeWatchdogActions {
    public let prepareLogs: () throws -> Void
    public let activeManagedOperation: () -> RuntimeOperation?
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let executeInitialSnapshotDecision: (
        WatchdogRuntimeInitialSnapshotDecision,
        RuntimeHealthSnapshot
    ) throws -> RuntimeWatchdogInitialSnapshotExecutionResult
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
        ) throws -> RuntimeWatchdogInitialSnapshotExecutionResult,
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

public struct RuntimeWatchdogRunner {
    private let actions: RuntimeWatchdogActions
    private let log: (String) -> Void
    private let printLine: (String) -> Void
    private var useCase: WatchdogRuntimeUseCase {
        WatchdogRuntimeUseCase()
    }

    public init(
        actions: RuntimeWatchdogActions,
        log: @escaping (String) -> Void,
        printLine: @escaping (String) -> Void
    ) {
        self.actions = actions
        self.log = log
        self.printLine = printLine
    }

    public func run() throws {
        try actions.prepareLogs()

        if let activeOperation = actions.activeManagedOperation() {
            let plan = useCase.activeOperationSkipPlan(activeOperation)
            log(plan.logMessage)
            actions.recordLifecycleEvent(.watchdog, plan.lifecycleMessage, plan.eventType)
            printLine(plan.printMessage)
            return
        }

        let initial = actions.healthSnapshot()
        let initialSnapshotResult = try actions.executeInitialSnapshotDecision(
            useCase.initialSnapshotDecision(initial),
            initial
        )
        if initialSnapshotResult == .handled {
            return
        }

        let proxyLivenessHTTP = actions.proxyLivenessHTTP(initial.proxyPort)
        try actions.executeRecoveryDecision(useCase.recoveryDecision(
            snapshot: initial,
            hostProxyLivenessHTTP: proxyLivenessHTTP,
            automaticRecoveryEnabled: actions.automaticRecoveryEnabled()
        ), initial)
    }
}

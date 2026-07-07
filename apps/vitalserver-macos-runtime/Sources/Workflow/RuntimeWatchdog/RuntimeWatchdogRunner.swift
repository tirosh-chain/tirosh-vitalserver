import Application
import Contracts
import Domain
import Foundation

public struct RuntimeWatchdogRunner {
    private let useCase: WatchdogRuntimeUseCase

    public init(useCase: WatchdogRuntimeUseCase = WatchdogRuntimeUseCase()) {
        self.useCase = useCase
    }

    public func run(
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws {
        prepareLogs(operations: operations, log: log)

        if let activeOperation = operations.activeManagedOperation() {
            let plan = useCase.activeOperationSkipPlan(activeOperation)
            log(plan.logMessage)
            operations.recordLifecycleEvent(.watchdog, plan.lifecycleMessage, plan.eventType)
            printLine(plan.printMessage)
            return
        }

        let initial = operations.healthSnapshot()
        let initialSnapshotResult = try executeInitialSnapshotDecision(
            useCase.initialSnapshotDecision(initial),
            snapshot: initial,
            operations: operations,
            log: log,
            printLine: printLine
        )
        if initialSnapshotResult == .handled {
            return
        }

        let proxyLivenessHTTP = operations.proxyLivenessHTTP(initial.proxyPort)
        try executeRecoveryDecision(useCase.recoveryDecision(
            snapshot: initial,
            hostProxyLivenessHTTP: proxyLivenessHTTP,
            automaticRecoveryEnabled: try operations.automaticRecoveryEnabled()
        ), snapshot: initial, operations: operations, log: log, printLine: printLine)
    }

    private func prepareLogs(
        operations: RuntimeWatchdogActions,
        log: (String) -> Void
    ) {
        logPrepareFailure(
            operations.createLogsDirectory(),
            prefix: "watchdog log directory preparation failed",
            log: log
        )
        logPrepareFailure(
            operations.rotateRuntimeLogs(),
            prefix: "watchdog log rotation failed",
            log: log
        )
        logPrepareFailure(
            operations.collectGuestLogs(),
            prefix: "watchdog guest log collection failed",
            log: log
        )
    }

    private func logPrepareFailure(
        _ result: RuntimeBestEffortOperationResult,
        prefix: String,
        log: (String) -> Void
    ) {
        guard case .failed(let reason) = result else {
            return
        }
        log("\(prefix) error=\(reason)")
    }

    private func executeInitialSnapshotDecision(
        _ decision: WatchdogRuntimeInitialSnapshotDecision,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws -> RuntimeWatchdogInitialSnapshotExecutionResult {
        switch decision {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(snapshot, operations: operations, log: log)
            try operations.writeRuntimeStatus(.healthy, .watchdog, plan.statusMessage)
            operations.recordObservedStatus(.healthy, .watchdog, plan.statusMessage, finalized)
            printLine(plan.printMessage)
            return .handled
        case .recoverySuppressed(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations, log: log, printLine: printLine)
            return .handled
        case .recoveryDeferred(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations, log: log, printLine: printLine)
            return .handled
        case .needsRecoveryProbe:
            return .needsRecoveryProbe
        }
    }

    private func writeObservedStatus(
        _ plan: WatchdogRuntimeObservedStatusPlan,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws {
        let snapshot = completeReachableVMLifecycleIfNeeded(snapshot, operations: operations, log: log)
        let plan = useCase.observedStatusPlan(
            plan,
            currentStatus: operations.currentRuntimeStatus()
        )
        if let logMessage = plan.logMessage {
            log(logMessage)
        }
        try operations.writeRuntimeStatus(plan.status, .watchdog, plan.message)
        operations.recordObservedStatus(plan.status, .watchdog, plan.message, snapshot)
        operations.recordObservedEvent(plan.status, .watchdog, plan.message, snapshot, plan.eventType)
        printLine(plan.printMessage)
    }

    private func completeReachableVMLifecycleIfNeeded(
        _ snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void
    ) -> RuntimeHealthSnapshot {
        guard snapshot.vmService == .loaded,
              snapshot.vmIP != nil,
              isSuccessfulHTTPStatus(snapshot.guestHTTP),
              isSuccessfulHTTPStatus(snapshot.hostProxyHTTP)
        else {
            return snapshot
        }
        return completeVMLifecycleIfNeeded(
            snapshot,
            operations: operations,
            log: log,
            markReason: "Guest control and host proxy reported reachable",
            eventMessage: "VM lifecycle marked running after reachable runtime observation"
        )
    }

    private func completeHealthyVMLifecycleIfNeeded(
        _ snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void
    ) -> RuntimeHealthSnapshot {
        let plan = useCase.lifecycleMarkPlan(snapshot)
        return completeVMLifecycleIfNeeded(
            snapshot,
            operations: operations,
            log: log,
            markReason: "Guest runtime reported healthy",
            eventMessage: plan.eventMessage
        )
    }

    private func completeVMLifecycleIfNeeded(
        _ snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        markReason: String,
        eventMessage: String
    ) -> RuntimeHealthSnapshot {
        let plan = useCase.lifecycleMarkPlan(snapshot)
        guard let lifecycle = plan.lifecycle else {
            return snapshot
        }
        do {
            try operations.markVMLifecycleRunning(lifecycle, markReason)
            operations.recordLifecycleEvent(.watchdog, eventMessage, .statusChanged)
            return operations.healthSnapshot()
        } catch {
            log(useCase.lifecycleMarkFailedLogMessage(error: error))
            return snapshot
        }
    }

    private func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private func executeRecoveryDecision(
        _ decision: WatchdogRuntimeRecoveryDecision,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws {
        switch decision {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(snapshot, operations: operations, log: log)
            try operations.writeRuntimeStatus(.healthy, .watchdog, plan.statusMessage)
            operations.recordObservedStatus(.healthy, .watchdog, plan.statusMessage, finalized)
            printLine(plan.printMessage)
        case .recoveryDisabled(let plan):
            try writeTerminalRecoveryStatus(plan, snapshot: snapshot, operations: operations, log: log, printLine: printLine)
        case .recoveryDeferred(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations, log: log, printLine: printLine)
        case .recoverySuppressed(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations, log: log, printLine: printLine)
        case .unrecoverable(let plan):
            try writeTerminalRecoveryStatus(plan, snapshot: snapshot, operations: operations, log: log, printLine: printLine)
        case .recover(let plan):
            try recover(plan, initial: snapshot, operations: operations, log: log, printLine: printLine)
        }
    }

    private func writeTerminalRecoveryStatus(
        _ plan: WatchdogRuntimeTerminalRecoveryPlan,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws {
        log(plan.detectedLogMessage)
        try operations.writeRuntimeStatus(.recovering, .watchdog, plan.startedStatusMessage)
        operations.recordObservedStatus(.recovering, .watchdog, plan.startedStatusMessage, snapshot)
        try operations.writeRuntimeStatus(plan.finalStatus, .watchdog, plan.finalStatusMessage)
        operations.recordObservedStatus(plan.finalStatus, .watchdog, plan.finalStatusMessage, snapshot)
        printLine(plan.printMessage)
    }

    private func recover(
        _ plan: WatchdogRuntimeRecoveryExecutionPlan,
        initial: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws {
        log(plan.detectedLogMessage)
        try operations.writeRuntimeStatus(.recovering, .watchdog, plan.startedStatusMessage)
        operations.recordObservedStatus(.recovering, .watchdog, plan.startedStatusMessage, initial)
        log(plan.planLogMessage)
        operations.recordObservedEvent(
            .recovering,
            .watchdog,
            plan.plannedEventMessage,
            initial,
            .recoveryPlanned
        )

        if let guestStackReconcileEventMessage = plan.guestStackReconcileEventMessage {
            operations.recordObservedEvent(
                .recovering,
                .watchdog,
                guestStackReconcileEventMessage,
                initial,
                .serviceRestartDispatched
            )
            do {
                try operations.reconcileGuestStack()
            } catch {
                let failurePlan = useCase.guestStackReconcileFailurePlan(error: error)
                try writeCommandFailure(failurePlan, snapshot: initial, operations: operations, log: log, printLine: printLine)
                return
            }
        }
        if let vmRestartEventMessage = plan.vmRestartEventMessage {
            operations.recordObservedEvent(
                .recovering,
                .watchdog,
                vmRestartEventMessage,
                initial,
                .serviceRestartDispatched
            )
            do {
                try operations.restartVMRuntime()
            } catch {
                let failurePlan = useCase.commandFailurePlan(service: .vm, error: error)
                try writeCommandFailure(failurePlan, snapshot: initial, operations: operations, log: log, printLine: printLine)
                return
            }
        }
        if let proxyRestartEventMessage = plan.proxyRestartEventMessage {
            operations.recordObservedEvent(
                .recovering,
                .watchdog,
                proxyRestartEventMessage,
                initial,
                .serviceRestartDispatched
            )
            do {
                try operations.restartService(.proxy)
            } catch {
                let failurePlan = useCase.commandFailurePlan(service: .proxy, error: error)
                try writeCommandFailure(failurePlan, snapshot: initial, operations: operations, log: log, printLine: printLine)
                return
            }
        }

        operations.sleep(operations.recoveryWaitSeconds)
        let recovered = operations.healthSnapshot()
        let completionPlan = useCase.recoveryCompletionPlan(recovered)
        try operations.writeRuntimeStatus(completionPlan.status, .watchdog, completionPlan.message)
        operations.recordObservedStatus(completionPlan.status, .watchdog, completionPlan.message, recovered)
        printLine(completionPlan.printMessage)
    }

    private func writeCommandFailure(
        _ plan: WatchdogRuntimeCommandFailurePlan,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogActions,
        log: (String) -> Void,
        printLine: (String) -> Void
    ) throws {
        log(plan.message)
        try operations.writeRuntimeStatus(plan.status, .watchdog, plan.message)
        operations.recordObservedStatus(plan.status, .watchdog, plan.message, snapshot)
        operations.recordObservedEvent(plan.status, .watchdog, plan.message, snapshot, plan.eventType)
        printLine(plan.printMessage)
    }
}

public enum RuntimeWatchdogInitialSnapshotExecutionResult: Equatable, Sendable {
    case handled
    case needsRecoveryProbe
}

public struct RuntimeWatchdogActions {
    public let createLogsDirectory: () -> RuntimeBestEffortOperationResult
    public let rotateRuntimeLogs: () -> RuntimeBestEffortOperationResult
    public let collectGuestLogs: () -> RuntimeBestEffortOperationResult
    public let activeManagedOperation: () -> RuntimeOperation?
    public let currentRuntimeStatus: () -> RuntimeStatusDocumentLoadResult
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let proxyLivenessHTTP: (Int?) -> String
    public let automaticRecoveryEnabled: () throws -> Bool
    public let reconcileGuestStack: () throws -> Void
    public let restartVMRuntime: () throws -> Void
    public let restartService: (RuntimeManagedService) throws -> Void
    public let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public let recordObservedStatus: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) -> Void
    public let recordObservedEvent: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) -> Void
    public let recordLifecycleEvent: (RuntimeOperation, String, RuntimeEventType) -> Void
    public let markVMLifecycleRunning: (RuntimeVMLifecycleDocument, String) throws -> Void
    public let recoveryWaitSeconds: TimeInterval
    public let sleep: (TimeInterval) -> Void

    public init(
        createLogsDirectory: @escaping () -> RuntimeBestEffortOperationResult,
        rotateRuntimeLogs: @escaping () -> RuntimeBestEffortOperationResult,
        collectGuestLogs: @escaping () -> RuntimeBestEffortOperationResult,
        activeManagedOperation: @escaping () -> RuntimeOperation?,
        currentRuntimeStatus: @escaping () -> RuntimeStatusDocumentLoadResult,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        proxyLivenessHTTP: @escaping (Int?) -> String,
        automaticRecoveryEnabled: @escaping () throws -> Bool,
        reconcileGuestStack: @escaping () throws -> Void,
        restartVMRuntime: @escaping () throws -> Void,
        restartService: @escaping (RuntimeManagedService) throws -> Void,
        writeRuntimeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        recordObservedStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) -> Void,
        recordObservedEvent: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot,
            RuntimeEventType
        ) -> Void,
        recordLifecycleEvent: @escaping (RuntimeOperation, String, RuntimeEventType) -> Void,
        markVMLifecycleRunning: @escaping (RuntimeVMLifecycleDocument, String) throws -> Void,
        recoveryWaitSeconds: TimeInterval,
        sleep: @escaping (TimeInterval) -> Void
    ) {
        self.createLogsDirectory = createLogsDirectory
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.collectGuestLogs = collectGuestLogs
        self.activeManagedOperation = activeManagedOperation
        self.currentRuntimeStatus = currentRuntimeStatus
        self.healthSnapshot = healthSnapshot
        self.proxyLivenessHTTP = proxyLivenessHTTP
        self.automaticRecoveryEnabled = automaticRecoveryEnabled
        self.reconcileGuestStack = reconcileGuestStack
        self.restartVMRuntime = restartVMRuntime
        self.restartService = restartService
        self.writeRuntimeStatus = writeRuntimeStatus
        self.recordObservedStatus = recordObservedStatus
        self.recordObservedEvent = recordObservedEvent
        self.recordLifecycleEvent = recordLifecycleEvent
        self.markVMLifecycleRunning = markVMLifecycleRunning
        self.recoveryWaitSeconds = recoveryWaitSeconds
        self.sleep = sleep
    }
}

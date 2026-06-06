import Application
import Contracts
import Foundation
import OutboundAdapters
import Workflow
import Errors

public struct RuntimeWatchdogRunnerCompositionContext {
    let installedPaths: InstalledRuntimePaths
    let logsDirectory: URL

    public init(
        installedPaths: InstalledRuntimePaths,
        logsDirectory: URL
    ) {
        self.installedPaths = installedPaths
        self.logsDirectory = logsDirectory
    }
}

public struct RuntimeWatchdogRunnerCompositionOperations {
    let fileStore: RuntimeFileStore
    let now: () -> Date
    let activeManagedOperation: () -> RuntimeOperation?
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let httpStatusCode: (String) -> String
    let automaticRecoveryEnabled: () -> Bool
    let restartVMRuntime: () throws -> Void
    let restartService: (RuntimeManagedService) throws -> Void
    let rotateRuntimeLogs: () throws -> Void
    let collectGuestLogs: () throws -> Void
    let writeRuntimeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    let recordObservedStatus: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot
    ) -> Void
    let recordObservedEvent: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) -> Void
    let recordLifecycleEvent: (RuntimeOperation, String, RuntimeEventType) -> Void
    let sleep: (TimeInterval) -> Void
    let log: (String) -> Void
    let printLine: (String) -> Void

    public init(
        fileStore: RuntimeFileStore,
        now: @escaping () -> Date,
        activeManagedOperation: @escaping () -> RuntimeOperation?,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        httpStatusCode: @escaping (String) -> String,
        automaticRecoveryEnabled: @escaping () -> Bool,
        restartVMRuntime: @escaping () throws -> Void,
        restartService: @escaping (RuntimeManagedService) throws -> Void,
        rotateRuntimeLogs: @escaping () throws -> Void,
        collectGuestLogs: @escaping () throws -> Void,
        writeRuntimeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        recordObservedStatus: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot
        ) -> Void,
        recordObservedEvent: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot,
            RuntimeEventType
        ) -> Void,
        recordLifecycleEvent: @escaping (RuntimeOperation, String, RuntimeEventType) -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void,
        printLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.fileStore = fileStore
        self.now = now
        self.activeManagedOperation = activeManagedOperation
        self.healthSnapshot = healthSnapshot
        self.httpStatusCode = httpStatusCode
        self.automaticRecoveryEnabled = automaticRecoveryEnabled
        self.restartVMRuntime = restartVMRuntime
        self.restartService = restartService
        self.rotateRuntimeLogs = rotateRuntimeLogs
        self.collectGuestLogs = collectGuestLogs
        self.writeRuntimeStatus = writeRuntimeStatus
        self.recordObservedStatus = recordObservedStatus
        self.recordObservedEvent = recordObservedEvent
        self.recordLifecycleEvent = recordLifecycleEvent
        self.sleep = sleep
        self.log = log
        self.printLine = printLine
    }
}

public enum RuntimeWatchdogRunnerComposition {
    public static func make(
        context: RuntimeWatchdogRunnerCompositionContext,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) -> RuntimeWatchdogRunner {
        RuntimeWatchdogRunner(
            actions: RuntimeWatchdogActions(
                prepareLogs: {
                    prepareLogs(context: context, operations: operations)
                },
                activeManagedOperation: operations.activeManagedOperation,
                healthSnapshot: operations.healthSnapshot,
                executeInitialSnapshotDecision: { decision, snapshot in
                    try executeInitialSnapshotDecision(
                        decision,
                        snapshot: snapshot,
                        context: context,
                        operations: operations
                    )
                },
                proxyLivenessHTTP: { port in
                    operations.httpStatusCode(Constants.Runtime.proxyLivenessURL(port: port))
                },
                automaticRecoveryEnabled: operations.automaticRecoveryEnabled,
                executeRecoveryDecision: { decision, snapshot in
                    try executeRecoveryDecision(
                        decision,
                        snapshot: snapshot,
                        context: context,
                        operations: operations
                    )
                },
                recordLifecycleEvent: operations.recordLifecycleEvent
            ),
            log: operations.log,
            printLine: operations.printLine
        )
    }

    private static func executeInitialSnapshotDecision(
        _ decision: WatchdogRuntimeInitialSnapshotDecision,
        snapshot: RuntimeHealthSnapshot,
        context: RuntimeWatchdogRunnerCompositionContext,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) throws -> RuntimeWatchdogInitialSnapshotExecutionResult {
        switch decision {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(snapshot, context: context, operations: operations)
            try operations.writeRuntimeStatus(.healthy, .watchdog, plan.statusMessage)
            operations.recordObservedStatus(.healthy, .watchdog, plan.statusMessage, finalized)
            operations.printLine(plan.printMessage)
            return .handled
        case .recoverySuppressed(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations)
            return .handled
        case .recoveryDeferred(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations)
            return .handled
        case .needsRecoveryProbe:
            return .needsRecoveryProbe
        }
    }

    private static func writeObservedStatus(
        _ plan: WatchdogRuntimeObservedStatusPlan,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) throws {
        if let logMessage = plan.logMessage {
            operations.log(logMessage)
        }
        try operations.writeRuntimeStatus(plan.status, .watchdog, plan.message)
        operations.recordObservedStatus(plan.status, .watchdog, plan.message, snapshot)
        operations.recordObservedEvent(plan.status, .watchdog, plan.message, snapshot, plan.eventType)
        operations.printLine(plan.printMessage)
    }

    private static func completeHealthyVMLifecycleIfNeeded(
        _ snapshot: RuntimeHealthSnapshot,
        context: RuntimeWatchdogRunnerCompositionContext,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) -> RuntimeHealthSnapshot {
        let useCase = WatchdogRuntimeUseCase()
        let plan = useCase.lifecycleMarkPlan(snapshot)
        guard let lifecycle = plan.lifecycle else {
            return snapshot
        }
        do {
            let timestamp = operations.now()
            try RuntimeVMLifecycleStore(
                url: context.installedPaths.vmLifecycle,
                fileStore: operations.fileStore,
                now: { timestamp }
            ).write(
                state: .running,
                operation: lifecycle.operation,
                message: "Guest runtime reported healthy"
            )
            operations.recordLifecycleEvent(.watchdog, plan.eventMessage, .statusChanged)
            return operations.healthSnapshot()
        } catch {
            operations.log(useCase.lifecycleMarkFailedLogMessage(error: error))
            return snapshot
        }
    }

    private static func executeRecoveryDecision(
        _ decision: WatchdogRuntimeRecoveryDecision,
        snapshot: RuntimeHealthSnapshot,
        context: RuntimeWatchdogRunnerCompositionContext,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) throws {
        switch decision {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(snapshot, context: context, operations: operations)
            try operations.writeRuntimeStatus(.healthy, .watchdog, plan.statusMessage)
            operations.recordObservedStatus(.healthy, .watchdog, plan.statusMessage, finalized)
            operations.printLine(plan.printMessage)
        case .recoveryDisabled(let plan):
            try writeTerminalRecoveryStatus(plan, snapshot: snapshot, operations: operations)
        case .recoveryDeferred(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations)
        case .recoverySuppressed(let plan):
            try writeObservedStatus(plan, snapshot: snapshot, operations: operations)
        case .unrecoverable(let plan):
            try writeTerminalRecoveryStatus(plan, snapshot: snapshot, operations: operations)
        case .recover(let plan):
            try recover(plan, initial: snapshot, operations: operations)
        }
    }

    private static func writeTerminalRecoveryStatus(
        _ plan: WatchdogRuntimeTerminalRecoveryPlan,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) throws {
        operations.log(plan.detectedLogMessage)
        try operations.writeRuntimeStatus(.recovering, .watchdog, plan.startedStatusMessage)
        operations.recordObservedStatus(.recovering, .watchdog, plan.startedStatusMessage, snapshot)
        try operations.writeRuntimeStatus(plan.finalStatus, .watchdog, plan.finalStatusMessage)
        operations.recordObservedStatus(plan.finalStatus, .watchdog, plan.finalStatusMessage, snapshot)
        operations.printLine(plan.printMessage)
    }

    private static func recover(
        _ plan: WatchdogRuntimeRecoveryExecutionPlan,
        initial: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) throws {
        let useCase = WatchdogRuntimeUseCase()
        operations.log(plan.detectedLogMessage)
        try operations.writeRuntimeStatus(.recovering, .watchdog, plan.startedStatusMessage)
        operations.recordObservedStatus(.recovering, .watchdog, plan.startedStatusMessage, initial)
        operations.log(plan.planLogMessage)
        operations.recordObservedEvent(
            .recovering,
            .watchdog,
            plan.plannedEventMessage,
            initial,
            .recoveryPlanned
        )

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
                try writeCommandFailure(failurePlan, snapshot: initial, operations: operations)
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
                try writeCommandFailure(failurePlan, snapshot: initial, operations: operations)
                return
            }
        }

        operations.sleep(Constants.Runtime.watchdogRecoveryWaitSeconds)
        let recovered = operations.healthSnapshot()
        let completionPlan = useCase.recoveryCompletionPlan(recovered)
        try operations.writeRuntimeStatus(completionPlan.status, .watchdog, completionPlan.message)
        operations.recordObservedStatus(completionPlan.status, .watchdog, completionPlan.message, recovered)
        operations.printLine(completionPlan.printMessage)
    }

    private static func writeCommandFailure(
        _ plan: WatchdogRuntimeCommandFailurePlan,
        snapshot: RuntimeHealthSnapshot,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) throws {
        operations.log(plan.message)
        try operations.writeRuntimeStatus(plan.status, .watchdog, plan.message)
        operations.recordObservedStatus(plan.status, .watchdog, plan.message, snapshot)
        operations.recordObservedEvent(plan.status, .watchdog, plan.message, snapshot, plan.eventType)
        operations.printLine(plan.printMessage)
    }

    private static func prepareLogs(
        context: RuntimeWatchdogRunnerCompositionContext,
        operations: RuntimeWatchdogRunnerCompositionOperations
    ) {
        do {
            try operations.fileStore.createDirectory(at: context.logsDirectory, withIntermediateDirectories: true)
        } catch {
            operations.log("watchdog log directory preparation failed error=\(error.localizedDescription)")
        }
        do {
            try operations.rotateRuntimeLogs()
        } catch {
            operations.log("watchdog log rotation failed error=\(error.localizedDescription)")
        }
        do {
            try operations.collectGuestLogs()
        } catch {
            operations.log("watchdog guest log collection failed error=\(error.localizedDescription)")
        }
    }
}

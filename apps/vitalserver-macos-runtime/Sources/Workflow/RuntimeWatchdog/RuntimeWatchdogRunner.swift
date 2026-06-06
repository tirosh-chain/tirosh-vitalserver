import Application
import Contracts
import Foundation
import Errors

public struct RuntimeWatchdogContext: Equatable, Sendable {
    public let recoveryWaitSeconds: TimeInterval

    public init(recoveryWaitSeconds: TimeInterval) {
        self.recoveryWaitSeconds = recoveryWaitSeconds
    }
}

public struct RuntimeWatchdogActions {
    public let prepareLogs: () throws -> Void
    public let activeManagedOperation: () -> RuntimeOperation?
    public let healthSnapshot: () -> RuntimeHealthSnapshot
    public let proxyLivenessHTTP: (Int) -> String
    public let automaticRecoveryEnabled: () -> Bool
    public let restartVMRuntime: () throws -> Void
    public let restartService: (RuntimeManagedService) throws -> Void
    public let markVMLifecycleRunning: (RuntimeVMLifecycleDocument) throws -> Void
    public let sleep: (TimeInterval) -> Void
    public let writeObservedStatus: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) throws -> Void
    public let recordObservedEvent: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) -> Void
    public let recordLifecycleEvent: (RuntimeOperation, String, RuntimeEventType) -> Void

    public init(
        prepareLogs: @escaping () throws -> Void,
        activeManagedOperation: @escaping () -> RuntimeOperation?,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        proxyLivenessHTTP: @escaping (Int) -> String,
        automaticRecoveryEnabled: @escaping () -> Bool,
        restartVMRuntime: @escaping () throws -> Void,
        restartService: @escaping (RuntimeManagedService) throws -> Void,
        markVMLifecycleRunning: @escaping (RuntimeVMLifecycleDocument) throws -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        writeObservedStatus: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot
        ) throws -> Void,
        recordObservedEvent: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot,
            RuntimeEventType
        ) -> Void,
        recordLifecycleEvent: @escaping (RuntimeOperation, String, RuntimeEventType) -> Void
    ) {
        self.prepareLogs = prepareLogs
        self.activeManagedOperation = activeManagedOperation
        self.healthSnapshot = healthSnapshot
        self.proxyLivenessHTTP = proxyLivenessHTTP
        self.automaticRecoveryEnabled = automaticRecoveryEnabled
        self.restartVMRuntime = restartVMRuntime
        self.restartService = restartService
        self.markVMLifecycleRunning = markVMLifecycleRunning
        self.sleep = sleep
        self.writeObservedStatus = writeObservedStatus
        self.recordObservedEvent = recordObservedEvent
        self.recordLifecycleEvent = recordLifecycleEvent
    }
}

public struct RuntimeWatchdogRunner {
    private let context: RuntimeWatchdogContext
    private let actions: RuntimeWatchdogActions
    private let log: (String) -> Void
    private let printLine: (String) -> Void
    private var useCase: WatchdogRuntimeUseCase {
        WatchdogRuntimeUseCase()
    }

    public init(
        context: RuntimeWatchdogContext,
        actions: RuntimeWatchdogActions,
        log: @escaping (String) -> Void,
        printLine: @escaping (String) -> Void
    ) {
        self.context = context
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
        switch useCase.initialSnapshotDecision(initial) {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(initial)
            try actions.writeObservedStatus(.healthy, .watchdog, plan.statusMessage, finalized)
            printLine(plan.printMessage)
            return
        case .recoverySuppressed(let plan):
            try writeObservedStatus(plan, snapshot: initial)
            return
        case .recoveryDeferred(let plan):
            try writeObservedStatus(plan, snapshot: initial)
            return
        case .needsRecoveryProbe:
            break
        }

        let proxyLivenessHTTP = actions.proxyLivenessHTTP(initial.proxyPort)
        switch useCase.recoveryDecision(
            snapshot: initial,
            hostProxyLivenessHTTP: proxyLivenessHTTP,
            automaticRecoveryEnabled: actions.automaticRecoveryEnabled()
        ) {
        case .healthy(let plan):
            let finalized = completeHealthyVMLifecycleIfNeeded(initial)
            try actions.writeObservedStatus(.healthy, .watchdog, plan.statusMessage, finalized)
            printLine(plan.printMessage)
            return

        case .recoveryDisabled(let plan):
            try writeTerminalRecoveryStatus(plan, snapshot: initial)
            return

        case .recoveryDeferred(let plan):
            try writeObservedStatus(plan, snapshot: initial)
            return

        case .recoverySuppressed(let plan):
            try writeObservedStatus(plan, snapshot: initial)
            return

        case .unrecoverable(let plan):
            try writeTerminalRecoveryStatus(plan, snapshot: initial)
            return

        case .recover(let plan):
            try recover(plan, initial: initial)
        }
    }

    private func writeObservedStatus(
        _ plan: WatchdogRuntimeObservedStatusPlan,
        snapshot: RuntimeHealthSnapshot
    ) throws {
        if let logMessage = plan.logMessage {
            log(logMessage)
        }
        try actions.writeObservedStatus(plan.status, .watchdog, plan.message, snapshot)
        actions.recordObservedEvent(
            plan.status,
            .watchdog,
            plan.message,
            snapshot,
            plan.eventType
        )
        printLine(plan.printMessage)
    }

    private func writeTerminalRecoveryStatus(
        _ plan: WatchdogRuntimeTerminalRecoveryPlan,
        snapshot: RuntimeHealthSnapshot
    ) throws {
        log(plan.detectedLogMessage)
        try actions.writeObservedStatus(.recovering, .watchdog, plan.startedStatusMessage, snapshot)
        try actions.writeObservedStatus(plan.finalStatus, .watchdog, plan.finalStatusMessage, snapshot)
        printLine(plan.printMessage)
    }

    private func completeHealthyVMLifecycleIfNeeded(_ snapshot: RuntimeHealthSnapshot) -> RuntimeHealthSnapshot {
        let plan = useCase.lifecycleMarkPlan(snapshot)
        guard let lifecycle = plan.lifecycle else {
            return snapshot
        }
        do {
            try actions.markVMLifecycleRunning(lifecycle)
            actions.recordLifecycleEvent(
                .watchdog,
                plan.eventMessage,
                .statusChanged
            )
            return actions.healthSnapshot()
        } catch {
            log(useCase.lifecycleMarkFailedLogMessage(error: error))
            return snapshot
        }
    }

    private func recover(
        _ plan: WatchdogRuntimeRecoveryExecutionPlan,
        initial: RuntimeHealthSnapshot
    ) throws {
        log(plan.detectedLogMessage)
        try actions.writeObservedStatus(.recovering, .watchdog, plan.startedStatusMessage, initial)
        log(plan.planLogMessage)
        actions.recordObservedEvent(
            .recovering,
            .watchdog,
            plan.plannedEventMessage,
            initial,
            .recoveryPlanned
        )

        if let vmRestartEventMessage = plan.vmRestartEventMessage {
            actions.recordObservedEvent(
                .recovering,
                .watchdog,
                vmRestartEventMessage,
                initial,
                .serviceRestartDispatched
            )
            do {
                try actions.restartVMRuntime()
            } catch {
                let failurePlan = useCase.commandFailurePlan(service: .vm, error: error)
                log(failurePlan.message)
                try actions.writeObservedStatus(failurePlan.status, .watchdog, failurePlan.message, initial)
                actions.recordObservedEvent(
                    failurePlan.status,
                    .watchdog,
                    failurePlan.message,
                    initial,
                    failurePlan.eventType
                )
                printLine(failurePlan.printMessage)
                return
            }
        }
        if let proxyRestartEventMessage = plan.proxyRestartEventMessage {
            actions.recordObservedEvent(
                .recovering,
                .watchdog,
                proxyRestartEventMessage,
                initial,
                .serviceRestartDispatched
            )
            do {
                try actions.restartService(.proxy)
            } catch {
                let failurePlan = useCase.commandFailurePlan(service: .proxy, error: error)
                log(failurePlan.message)
                try actions.writeObservedStatus(failurePlan.status, .watchdog, failurePlan.message, initial)
                actions.recordObservedEvent(
                    failurePlan.status,
                    .watchdog,
                    failurePlan.message,
                    initial,
                    failurePlan.eventType
                )
                printLine(failurePlan.printMessage)
                return
            }
        }

        actions.sleep(context.recoveryWaitSeconds)
        let recovered = actions.healthSnapshot()
        let completionPlan = useCase.recoveryCompletionPlan(recovered)
        try actions.writeObservedStatus(completionPlan.status, .watchdog, completionPlan.message, recovered)
        printLine(completionPlan.printMessage)
    }
}

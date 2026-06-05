import Contracts
import Core
import Foundation

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
            let message = "watchdog skipped during active runtime operation operation=\(activeOperation.rawValue)"
            log(message)
            actions.recordLifecycleEvent(.watchdog, message, .watchdogSkipped)
            printLine("watchdog: skipped active operation")
            return
        }

        let initial = actions.healthSnapshot()
        if RuntimeHealthSnapshotPolicy.isHealthy(initial) {
            let finalized = completeHealthyVMLifecycleIfNeeded(initial)
            try actions.writeObservedStatus(.healthy, .watchdog, "runtime watchdog passed", finalized)
            printLine("watchdog: ok")
            return
        }

        if let suppressionReason = RuntimeWatchdogRecoveryPolicy.automaticRecoverySuppressionReason(initial) {
            try suppressRecovery(reason: suppressionReason, snapshot: initial)
            return
        }
        if let deferralReason = RuntimeWatchdogRecoveryPolicy.automaticRecoveryDeferralReason(initial) {
            try deferRecovery(reason: deferralReason, snapshot: initial)
            return
        }

        let proxyLivenessHTTP = actions.proxyLivenessHTTP(initial.proxyPort)
        let decision = RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: initial,
            hostProxyLivenessHTTP: proxyLivenessHTTP,
            automaticRecoveryEnabled: actions.automaticRecoveryEnabled()
        )

        switch decision {
        case .healthy:
            let finalized = completeHealthyVMLifecycleIfNeeded(initial)
            try actions.writeObservedStatus(.healthy, .watchdog, "runtime watchdog passed", finalized)
            printLine("watchdog: ok")
            return

        case .recoveryDisabled(let reason):
            log("watchdog detected unhealthy runtime reasons=\(reason)")
            try actions.writeObservedStatus(.recovering, .watchdog, "watchdog recovery started: \(reason)", initial)
            try actions.writeObservedStatus(
                .degraded,
                .watchdog,
                "watchdog detected unhealthy runtime; automatic recovery is disabled: \(reason)",
                initial
            )
            printLine("watchdog: recovery disabled")
            return

        case .recoveryDeferred(let reason):
            try deferRecovery(reason: reason, snapshot: initial)
            return

        case .recoverySuppressed(let reason):
            try suppressRecovery(reason: reason, snapshot: initial)
            return

        case .unrecoverable(let reason):
            log("watchdog detected unhealthy runtime reasons=\(reason)")
            try actions.writeObservedStatus(.recovering, .watchdog, "watchdog recovery started: \(reason)", initial)
            try actions.writeObservedStatus(
                .critical,
                .watchdog,
                "watchdog cannot recover missing installed artifacts: \(reason)",
                initial
            )
            printLine("watchdog: critical")
            return

        case .recover(let reason, let recoveryPlan):
            try recover(
                reason: reason,
                recoveryPlan: recoveryPlan,
                proxyLivenessHTTP: proxyLivenessHTTP,
                initial: initial
            )
        }
    }

    private func suppressRecovery(reason: String, snapshot: RuntimeHealthSnapshot) throws {
        let message = "watchdog recovery suppressed: \(reason)"
        log(message)
        try actions.writeObservedStatus(.critical, .watchdog, message, snapshot)
        actions.recordObservedEvent(
            .critical,
            .watchdog,
            message,
            snapshot,
            .recoverySuppressed
        )
        printLine("watchdog: suppressed")
    }

    private func completeHealthyVMLifecycleIfNeeded(_ snapshot: RuntimeHealthSnapshot) -> RuntimeHealthSnapshot {
        guard let lifecycle = snapshot.vmLifecycle,
              lifecycle.state == .starting || lifecycle.state == .bootstrapping
        else {
            return snapshot
        }
        do {
            try actions.markVMLifecycleRunning(lifecycle)
            actions.recordLifecycleEvent(
                .watchdog,
                "VM lifecycle marked running after healthy runtime observation",
                .statusChanged
            )
            return actions.healthSnapshot()
        } catch {
            log("watchdog failed to mark VM lifecycle running error=\(error.localizedDescription)")
            return snapshot
        }
    }

    private func deferRecovery(reason: String, snapshot: RuntimeHealthSnapshot) throws {
        let message = "watchdog recovery deferred: \(reason)"
        log(message)
        try actions.writeObservedStatus(.degraded, .watchdog, message, snapshot)
        actions.recordObservedEvent(
            .degraded,
            .watchdog,
            message,
            snapshot,
            .recoveryDeferred
        )
        printLine("watchdog: deferred")
    }

    private func recover(
        reason: String,
        recoveryPlan: RuntimeRecoveryPlan,
        proxyLivenessHTTP: String,
        initial: RuntimeHealthSnapshot
    ) throws {
        log("watchdog detected unhealthy runtime reasons=\(reason)")
        try actions.writeObservedStatus(.recovering, .watchdog, "watchdog recovery started: \(reason)", initial)
        let restartReasons = restartReasonText(recoveryPlan)
        log(
            "watchdog recovery plan vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy) "
                + "restartReasons=\(restartReasons) "
                + "hostProxyHealth=\(proxyLivenessHTTP) hostProxyReady=\(initial.hostProxyHTTP) guestReady=\(initial.guestHTTP)"
        )
        actions.recordObservedEvent(
            .recovering,
            .watchdog,
            "watchdog recovery planned vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy) reasons=\(restartReasons)",
            initial,
            .recoveryPlanned
        )

        if recoveryPlan.restartVM {
            actions.recordObservedEvent(
                .recovering,
                .watchdog,
                "watchdog restart dispatched services=vm,guest-log-sync",
                initial,
                .serviceRestartDispatched
            )
            do {
                try actions.restartVMRuntime()
            } catch {
                let message = "watchdog VM restart failed: \(error.localizedDescription)"
                log(message)
                try actions.writeObservedStatus(.critical, .watchdog, message, initial)
                actions.recordObservedEvent(
                    .critical,
                    .watchdog,
                    message,
                    initial,
                    .runtimeCommandFailed
                )
                printLine("watchdog: critical")
                return
            }
        }
        if recoveryPlan.restartProxy {
            actions.recordObservedEvent(
                .recovering,
                .watchdog,
                "watchdog restart dispatched services=proxy",
                initial,
                .serviceRestartDispatched
            )
            do {
                try actions.restartService(.proxy)
            } catch {
                let message = "watchdog proxy restart failed: \(error.localizedDescription)"
                log(message)
                try actions.writeObservedStatus(.critical, .watchdog, message, initial)
                actions.recordObservedEvent(
                    .critical,
                    .watchdog,
                    message,
                    initial,
                    .runtimeCommandFailed
                )
                printLine("watchdog: critical")
                return
            }
        }

        actions.sleep(context.recoveryWaitSeconds)
        let recovered = actions.healthSnapshot()
        if RuntimeHealthSnapshotPolicy.isHealthy(recovered) {
            try actions.writeObservedStatus(.healthy, .watchdog, "watchdog recovery completed", recovered)
            printLine("watchdog: recovered")
        } else {
            try actions.writeObservedStatus(
                .critical,
                .watchdog,
                "watchdog recovery failed: \(reasonText(recovered.failureReasons))",
                recovered
            )
            printLine("watchdog: critical")
        }
    }

    private func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        RuntimeFailureReasonText.describe(reasons)
    }

    private func restartReasonText(_ recoveryPlan: RuntimeRecoveryPlan) -> String {
        let reasonCodes = recoveryPlan.restartReasonCodes
        guard !reasonCodes.isEmpty else {
            return "none"
        }
        return reasonCodes.joined(separator: ",")
    }
}

import Foundation
import Core
import Contracts

struct RuntimeWatchdogActions {
    let prepareLogs: () throws -> Void
    let activeManagedOperation: () -> RuntimeOperation?
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let proxyLivenessHTTP: (Int) -> String
    let automaticRecoveryEnabled: () -> Bool
    let restartVMRuntime: () throws -> Void
    let restartService: (RuntimeManagedService) -> Void
    let sleep: (TimeInterval) -> Void
    let writeObservedStatus: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) throws -> Void
    let recordObservedEvent: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot, RuntimeEventType) -> Void
    let recordLifecycleEvent: (RuntimeOperation, String, RuntimeEventType) -> Void
}

struct RuntimeWatchdogRunner {
    private let actions: RuntimeWatchdogActions
    private let log: (String) -> Void

    init(
        actions: RuntimeWatchdogActions,
        log: @escaping (String) -> Void
    ) {
        self.actions = actions
        self.log = log
    }

    func run() throws {
        try actions.prepareLogs()

        if let activeOperation = actions.activeManagedOperation() {
            let message = "watchdog skipped during active runtime operation operation=\(activeOperation.rawValue)"
            log(message)
            actions.recordLifecycleEvent(.watchdog, message, .watchdogSkipped)
            print("watchdog: skipped active operation")
            return
        }

        let initial = actions.healthSnapshot()
        if RuntimeHealthSnapshotPolicy.isHealthy(initial) {
            try actions.writeObservedStatus(.healthy, .watchdog, "runtime watchdog passed", initial)
            print("watchdog: ok")
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
            try actions.writeObservedStatus(.healthy, .watchdog, "runtime watchdog passed", initial)
            print("watchdog: ok")
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
            print("watchdog: recovery disabled")
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
            print("watchdog: critical")
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
        print("watchdog: suppressed")
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
        print("watchdog: deferred")
    }

    private func recover(
        reason: String,
        recoveryPlan: RuntimeRecoveryPlan,
        proxyLivenessHTTP: String,
        initial: RuntimeHealthSnapshot
    ) throws {
        log("watchdog detected unhealthy runtime reasons=\(reason)")
        try actions.writeObservedStatus(.recovering, .watchdog, "watchdog recovery started: \(reason)", initial)
        log(
            "watchdog recovery plan vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy) "
                + "hostProxyHealth=\(proxyLivenessHTTP) hostProxyReady=\(initial.hostProxyHTTP) guestReady=\(initial.guestHTTP)"
        )
        actions.recordObservedEvent(
            .recovering,
            .watchdog,
            "watchdog recovery planned vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy)",
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
                print("watchdog: critical")
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
            actions.restartService(.proxy)
        }

        actions.sleep(Constants.Runtime.watchdogRecoveryWaitSeconds)
        let recovered = actions.healthSnapshot()
        if RuntimeHealthSnapshotPolicy.isHealthy(recovered) {
            try actions.writeObservedStatus(.healthy, .watchdog, "watchdog recovery completed", recovered)
            print("watchdog: recovered")
        } else {
            try actions.writeObservedStatus(
                .critical,
                .watchdog,
                "watchdog recovery failed: \(reasonText(recovered.failureReasons))",
                recovered
            )
            print("watchdog: critical")
        }
    }

    private func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        RuntimeFailureReasonText.describe(reasons)
    }
}

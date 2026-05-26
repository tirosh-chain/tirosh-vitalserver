import Foundation
import Core
import Contracts

struct RuntimeWatchdogActions {
    let prepareLogs: () throws -> Void
    let activeManagedOperation: () -> RuntimeOperation?
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let proxyLivenessHTTP: (Int) -> String
    let automaticRecoveryEnabled: () -> Bool
    let restartService: (RuntimeManagedService) -> Void
    let sleep: (TimeInterval) -> Void
    let writeObservedStatus: (RuntimeStatusLevel, RuntimeOperation, String, RuntimeHealthSnapshot) throws -> Void
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
            log("watchdog skipped during active runtime operation operation=\(activeOperation.rawValue)")
            print("watchdog: skipped active operation")
            return
        }

        let initial = actions.healthSnapshot()
        guard !initial.isHealthy else {
            try actions.writeObservedStatus(.healthy, .watchdog, "runtime watchdog passed", initial)
            print("watchdog: ok")
            return
        }

        let reasons = reasonText(initial.failureReasons)
        log("watchdog detected unhealthy runtime reasons=\(reasons)")
        try actions.writeObservedStatus(.recovering, .watchdog, "watchdog recovery started: \(reasons)", initial)

        let proxyLivenessHTTP = actions.proxyLivenessHTTP(initial.proxyPort)
        let recoveryPlan = RuntimeRecoveryPlanner.plan(RuntimeRecoveryInput(
            vmExecutable: initial.vmExecutable,
            proxyExecutable: initial.proxyExecutable,
            rootfsBase: initial.rootfsBase,
            vmDisk: initial.vmDisk,
            vmService: initial.vmService,
            proxyService: initial.proxyService,
            vmIP: initial.vmIP,
            guestHTTP: initial.guestHTTP,
            hostProxyReadinessHTTP: initial.hostProxyHTTP,
            hostProxyLivenessHTTP: proxyLivenessHTTP,
            containerObservation: initial.containerObservation
        ))
        log(
            "watchdog recovery plan vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy) "
                + "hostProxyHealth=\(proxyLivenessHTTP) hostProxyReady=\(initial.hostProxyHTTP) guestReady=\(initial.guestHTTP)"
        )

        guard actions.automaticRecoveryEnabled() else {
            try actions.writeObservedStatus(
                .degraded,
                .watchdog,
                "watchdog detected unhealthy runtime; automatic recovery is disabled: \(reasons)",
                initial
            )
            print("watchdog: recovery disabled")
            return
        }

        guard recoveryPlan.canRecover else {
            try actions.writeObservedStatus(
                .critical,
                .watchdog,
                "watchdog cannot recover missing installed artifacts: \(reasons)",
                initial
            )
            print("watchdog: critical")
            return
        }

        if recoveryPlan.restartVM {
            actions.restartService(.vm)
            actions.restartService(.guestLogSync)
        }
        if recoveryPlan.restartProxy {
            actions.restartService(.proxy)
        }

        actions.sleep(Constants.Runtime.watchdogRecoveryWaitSeconds)
        let recovered = actions.healthSnapshot()
        if recovered.isHealthy {
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
        reasons.isEmpty ? "unknown" : reasons.map(\.rawValue).joined(separator: ", ")
    }
}

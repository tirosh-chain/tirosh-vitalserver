import Foundation
import RuntimeCore

struct RuntimeWatchdogActions {
    let prepareLogs: () throws -> Void
    let activeManagedOperation: () -> RuntimeOperation?
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let proxyLivenessHTTP: (Int) -> String
    let automaticRecoveryEnabled: () -> Bool
    let restartService: (RuntimeManagedService) -> Void
    let sleep: (TimeInterval) -> Void
    let writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
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
            try actions.writeStatus(.healthy, .watchdog, "runtime watchdog passed")
            print("watchdog: ok")
            return
        }

        let reasons = reasonText(initial.failureReasons)
        log("watchdog detected unhealthy runtime reasons=\(reasons)")
        try actions.writeStatus(.recovering, .watchdog, "watchdog recovery started: \(reasons)")

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
            hostProxyLivenessHTTP: proxyLivenessHTTP
        ))
        log(
            "watchdog recovery plan vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy) "
                + "hostProxyHealth=\(proxyLivenessHTTP) hostProxyReady=\(initial.hostProxyHTTP) guestReady=\(initial.guestHTTP)"
        )

        guard actions.automaticRecoveryEnabled() else {
            try actions.writeStatus(
                .degraded,
                .watchdog,
                "watchdog detected unhealthy runtime; automatic recovery is disabled: \(reasons)"
            )
            print("watchdog: recovery disabled")
            return
        }

        guard recoveryPlan.canRecover else {
            try actions.writeStatus(
                .critical,
                .watchdog,
                "watchdog cannot recover missing installed artifacts: \(reasons)"
            )
            print("watchdog: critical")
            return
        }

        if recoveryPlan.restartVM {
            actions.restartService(.vm)
        }
        if recoveryPlan.restartProxy {
            actions.restartService(.proxy)
        }

        actions.sleep(Constants.Runtime.watchdogRecoveryWaitSeconds)
        let recovered = actions.healthSnapshot()
        if recovered.isHealthy {
            try actions.writeStatus(.healthy, .watchdog, "watchdog recovery completed")
            print("watchdog: recovered")
        } else {
            try actions.writeStatus(
                .critical,
                .watchdog,
                "watchdog recovery failed: \(reasonText(recovered.failureReasons))"
            )
            print("watchdog: critical")
        }
    }

    private func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        reasons.isEmpty ? "unknown" : reasons.map(\.rawValue).joined(separator: ", ")
    }
}

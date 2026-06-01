import Contracts
import Foundation

public enum RuntimeWatchdogRecoveryDecision: Equatable {
    case healthy
    case recoveryDisabled(reason: String)
    case recoveryDeferred(reason: String)
    case recoverySuppressed(reason: String)
    case unrecoverable(reason: String)
    case recover(reason: String, plan: RuntimeRecoveryPlan)
}

public enum RuntimeWatchdogRecoveryPolicy {
    public static func decision(
        snapshot: RuntimeHealthSnapshot,
        hostProxyLivenessHTTP: String,
        automaticRecoveryEnabled: Bool
    ) -> RuntimeWatchdogRecoveryDecision {
        if RuntimeHealthSnapshotPolicy.isHealthy(snapshot) {
            return .healthy
        }

        let reasons = reasonText(snapshot.failureReasons)
        if let suppressionReason = automaticRecoverySuppressionReason(snapshot) {
            return .recoverySuppressed(reason: suppressionReason)
        }
        if let deferralReason = automaticRecoveryDeferralReason(snapshot) {
            return .recoveryDeferred(reason: deferralReason)
        }

        guard automaticRecoveryEnabled else {
            return .recoveryDisabled(reason: reasons)
        }

        let plan = RuntimeRecoveryPlanner.plan(RuntimeRecoveryInput(
            vmExecutable: snapshot.vmExecutable,
            proxyExecutable: snapshot.proxyExecutable,
            rootfsBase: snapshot.rootfsBase,
            vmDisk: snapshot.vmDisk,
            vmService: snapshot.vmService,
            proxyService: snapshot.proxyService,
            vmLifecycle: snapshot.vmLifecycle,
            vmIP: snapshot.vmIP,
            guestHTTP: snapshot.guestHTTP,
            hostProxyReadinessHTTP: snapshot.hostProxyHTTP,
            hostProxyLivenessHTTP: hostProxyLivenessHTTP,
            containerObservation: snapshot.containerObservation
        ))

        guard plan.canRecover else {
            return .unrecoverable(reason: reasons)
        }
        return .recover(reason: reasons, plan: plan)
    }

    public static func automaticRecoverySuppressionReason(_ snapshot: RuntimeHealthSnapshot) -> String? {
        guard let protectedError = snapshot.vmErrors.first(where: { $0.requiresDataPreservationBeforeRecovery }) else {
            return nil
        }
        return protectedError.rawValue
    }

    public static func automaticRecoveryDeferralReason(
        _ snapshot: RuntimeHealthSnapshot,
        now: Date = Date()
    ) -> String? {
        guard let lifecycle = snapshot.vmLifecycle,
              lifecycle.isWaitingForGuest(at: now)
        else {
            return nil
        }
        return "vm-lifecycle-\(lifecycle.state.rawValue)"
    }

    private static func reasonText(_ reasons: [RuntimeFailureReason]) -> String {
        reasons.isEmpty ? "no failure reason reported" : reasons.map(\.rawValue).joined(separator: ", ")
    }
}

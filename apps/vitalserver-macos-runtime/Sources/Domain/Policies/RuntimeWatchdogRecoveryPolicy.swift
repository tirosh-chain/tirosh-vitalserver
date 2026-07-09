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
        if let missingFailureReasonIssue = RuntimeHealthSnapshotPolicy.missingFailureReasonIssue(snapshot) {
            return .unrecoverable(reason: missingFailureReasonIssue)
        }
        if let observationSourceIssue = observationSourceIssue(
            snapshot.failureReasons,
            guestServiceStatuses: snapshot.guestServiceStatuses,
            guestServiceResources: snapshot.guestServiceResources
        ) {
            return .unrecoverable(reason: observationSourceIssue.rawValue)
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
            guestServiceStatuses: snapshot.guestServiceStatuses,
            guestServiceResources: snapshot.guestServiceResources
        ))

        guard plan.canRecover else {
            if isOnlyServiceStateReadFailure(blockers: plan.blockers) {
                return .recoveryDeferred(reason: plan.blockers.isEmpty ? reasons : reasonText(plan.blockers))
            }
            return .unrecoverable(reason: plan.blockers.isEmpty ? reasons : reasonText(plan.blockers))
        }
        return .recover(reason: reasons, plan: plan)
    }

    private static func isOnlyServiceStateReadFailure(blockers: [String]) -> Bool {
        let vmServicePrefix = "recovery-blocked-vm-service-state-"
        let proxyServicePrefix = "recovery-blocked-proxy-service-state-"

        guard !blockers.isEmpty else {
            return false
        }

        return blockers.allSatisfy { blocker in
            blocker.hasPrefix(vmServicePrefix) || blocker.hasPrefix(proxyServicePrefix)
        }
    }

    public static func automaticRecoverySuppressionReason(_ snapshot: RuntimeHealthSnapshot) -> String? {
        if let protectedReason = snapshot.failureReasons.first(where: { $0.requiresDataPreservationBeforeRecovery }) {
            return protectedReason.rawValue
        }
        if let protectedError = snapshot.vmErrors.first(where: { $0.requiresDataPreservationBeforeRecovery }) {
            return RuntimeFailureReason(vmError: protectedError).rawValue
        }
        return nil
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

    private static func observationSourceIssue(
        _ reasons: [RuntimeFailureReason],
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]>,
        guestServiceResources: [RuntimeGuestServiceResource]
    ) -> RuntimeFailureReason? {
        if RuntimeObservationHealthPolicy.requiresGuestStackReconcile(
            guestServiceStatuses: guestServiceStatuses,
            guestServiceResources: guestServiceResources
        ) {
            return nil
        }
        return reasons.first { reason in
            switch reason {
            case .guestServiceObservationMissing, .guestServiceObservationReadFailed:
                return true
            default:
                return false
            }
        }
    }

    private static func reasonText(_ reasons: [String]) -> String {
        reasons.isEmpty ? "no failure reason reported" : reasons.joined(separator: ", ")
    }
}

import Contracts
import Foundation

public enum RuntimeObservationHealthPolicy {
    private static let criticalGuestServices: Set<String> = [
        "redis",
        "app",
        "recorder-recovery",
        "recorder-ingress",
        "vitaldb-observer",
        "edge",
    ]

    public static func failureReasons(
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported,
        guestServiceResources: [RuntimeGuestServiceResource] = [],
        guestServiceResourceReadIssues: [RuntimeGuestServiceResourceReadIssue] = []
    ) -> [RuntimeFailureReason] {
        var reasons: [RuntimeFailureReason] = []
        reasons.append(contentsOf: serviceFailureReasons(
            guestServiceStatuses,
            resources: guestServiceResources
        ))
        reasons.append(contentsOf: resourceReadIssueFailureReasons(guestServiceResourceReadIssues))
        return reasons
    }

    public static func requiresGuestStackReconcile(
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported,
        guestServiceResources: [RuntimeGuestServiceResource] = []
    ) -> Bool {
        switch guestServiceStatuses {
        case .loaded(let statuses):
            return !guestServiceFailureReasons(statuses, resources: guestServiceResources).isEmpty
        case .notReported, .missing, .readFailed:
            return false
        }
    }

    private static func serviceFailureReasons(
        _ guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]>,
        resources: [RuntimeGuestServiceResource]
    ) -> [RuntimeFailureReason] {
        switch guestServiceStatuses {
        case .loaded(let statuses):
            return guestServiceFailureReasons(statuses, resources: resources)
        case .missing:
            return [.guestServiceObservationMissing]
        case .readFailed(let message):
            return [.guestServiceObservationReadFailed(failureToken(message))]
        case .notReported:
            return []
        }
    }

    private static func guestServiceFailureReasons(
        _ statuses: [RuntimeGuestControlServiceStatus],
        resources: [RuntimeGuestServiceResource]
    ) -> [RuntimeFailureReason] {
        let resourceByService = Dictionary(
            uniqueKeysWithValues: resources.map { ($0.service, $0) }
        )
        return statuses.compactMap { status -> RuntimeFailureReason? in
            guard criticalGuestServices.contains(status.service),
                  let failureState = guestServiceFailureState(
                    status,
                    resource: resourceByService[status.service]
                  ) else {
                return nil
            }
            return .guestService(service: status.service, state: failureState)
        }
    }

    private static func guestServiceFailureState(
        _ status: RuntimeGuestControlServiceStatus,
        resource: RuntimeGuestServiceResource?
    ) -> String? {
        if let desiredState = resource?.spec.desiredState,
           desiredState == "stopped",
           status.state == "stopped" {
            return nil
        }
        if status.state != "running" {
            return normalizedState(status.state)
        }
        if let exitCode = status.exitCode, exitCode != 0 {
            return "exit-\(exitCode)"
        }
        if RuntimeHealthClassificationPolicy.isFailingContainerHealth(status.health) {
            return normalizedState(status.health)
        }
        return nil
    }

    private static func resourceReadIssueFailureReasons(
        _ issues: [RuntimeGuestServiceResourceReadIssue]
    ) -> [RuntimeFailureReason] {
        guard !issues.isEmpty else {
            return []
        }
        let message = issues
            .map { "\($0.service):\($0.message)" }
            .joined(separator: ",")
        return [.guestServiceObservationReadFailed(failureToken(message))]
    }

    public static func isRuntimeHealthAnomaly(_ anomaly: VitalDBAnomalyObservation) -> Bool {
        isRuntimeCriticalVitalDBAnomaly(anomaly)
    }

    public static func isOperatorVisibleOnlyAnomaly(_ anomaly: VitalDBAnomalyObservation) -> Bool {
        (anomaly.severity == .warning || anomaly.severity == .critical)
            && !isRuntimeCriticalVitalDBAnomaly(anomaly)
    }

    private static func isRuntimeCriticalVitalDBAnomaly(
        _ anomaly: VitalDBAnomalyObservation
    ) -> Bool {
        guard anomaly.severity == .critical else {
            return false
        }
        switch anomaly.kind {
        case .backendUnavailable, .observerUnhealthy:
            return true
        case .duplicateIP, .offline, .staleRecorder, .unknown:
            return false
        }
    }

    private static func normalizedState(_ value: String) -> String {
        failureToken(value)
    }

    private static func failureToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-"
                    || scalar == "_"
                    || scalar == "."
                    ? Character(scalar)
                    : "_"
            }
            .prefix(80)
            .map(String.init)
            .joined()
    }
}

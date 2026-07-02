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
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported
    ) -> [RuntimeFailureReason] {
        var reasons: [RuntimeFailureReason] = []
        reasons.append(contentsOf: serviceFailureReasons(guestServiceStatuses))
        return reasons
    }

    public static func requiresGuestStackReconcile(
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported
    ) -> Bool {
        switch guestServiceStatuses {
        case .loaded(let statuses):
            return !guestServiceFailureReasons(statuses).isEmpty
        case .notReported, .missing, .readFailed:
            return false
        }
    }

    private static func serviceFailureReasons(
        _ guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]>
    ) -> [RuntimeFailureReason] {
        switch guestServiceStatuses {
        case .loaded(let statuses):
            return guestServiceFailureReasons(statuses)
        case .missing:
            return [.guestServiceObservationMissing]
        case .readFailed(let message):
            return [.guestServiceObservationReadFailed(failureToken(message))]
        case .notReported:
            return []
        }
    }

    private static func guestServiceFailureReasons(
        _ statuses: [RuntimeGuestControlServiceStatus]
    ) -> [RuntimeFailureReason] {
        statuses.compactMap { status in
            guard criticalGuestServices.contains(status.service),
                  let failureState = guestServiceFailureState(status) else {
                return nil
            }
            return .guestService(service: status.service, state: failureState)
        }
    }

    private static func guestServiceFailureState(
        _ status: RuntimeGuestControlServiceStatus
    ) -> String? {
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

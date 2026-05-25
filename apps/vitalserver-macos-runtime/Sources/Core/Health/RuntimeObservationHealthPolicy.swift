import Contracts
import Foundation

enum RuntimeObservationHealthPolicy {
    private static let criticalContainerServices: Set<String> = [
        "redis",
        "app",
        "audit-proxy",
        "vitaldb-observer",
        "edge",
    ]

    static func failureReasons(
        containerObservation: RuntimeContainerObservation?,
        vitalDBObservation: VitalDBObservationDocument?
    ) -> [RuntimeFailureReason] {
        var reasons: [RuntimeFailureReason] = []
        reasons.append(contentsOf: containerFailureReasons(containerObservation))
        reasons.append(contentsOf: vitalDBFailureReasons(vitalDBObservation))
        return reasons
    }

    static func requiresVMRestart(containerObservation: RuntimeContainerObservation?) -> Bool {
        !containerFailureReasons(containerObservation).isEmpty
    }

    private static func containerFailureReasons(
        _ observation: RuntimeContainerObservation?
    ) -> [RuntimeFailureReason] {
        guard let observation else {
            return []
        }
        return observation.composeServices.compactMap { service in
            guard criticalContainerServices.contains(service.service),
                  let failureState = containerFailureState(service) else {
                return nil
            }
            return .containerService(service: service.service, state: failureState)
        }
    }

    private static func containerFailureState(
        _ service: RuntimeContainerServiceObservation
    ) -> String? {
        if let state = service.state, state != "running" {
            return normalizedState(state)
        }
        if let exitCode = service.exitCode, exitCode != 0 {
            return "exit-\(exitCode)"
        }
        if let health = service.health,
           !health.isEmpty,
           health != "healthy" {
            return normalizedState(health)
        }
        return nil
    }

    private static func vitalDBFailureReasons(
        _ observation: VitalDBObservationDocument?
    ) -> [RuntimeFailureReason] {
        guard let observation else {
            return []
        }

        var reasons: [RuntimeFailureReason] = []
        if !observation.ready {
            reasons.append(.vitalDBAnomaly(
                kind: "observer-unhealthy",
                subject: failureToken(observation.source)
            ))
        }

        for anomaly in observation.anomalies where anomaly.severity == .critical {
            let reason = RuntimeFailureReason.vitalDBAnomaly(
                kind: failureToken(anomaly.kind.rawValue),
                subject: failureToken(anomaly.subject)
            )
            if !reasons.map(\.rawValue).contains(reason.rawValue) {
                reasons.append(reason)
            }
        }
        return reasons
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

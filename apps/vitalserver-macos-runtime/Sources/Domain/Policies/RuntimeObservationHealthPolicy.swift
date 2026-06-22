import Contracts
import Foundation

public enum RuntimeObservationHealthPolicy {
    private static let criticalContainerServices: Set<String> = [
        "redis",
        "app",
        "recorder-ingress",
        "vitaldb-observer",
        "edge",
    ]

    public static func failureReasons(
        containerObservation: RuntimeObservationInput<RuntimeContainerObservation>,
        vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument>
    ) -> [RuntimeFailureReason] {
        var reasons: [RuntimeFailureReason] = []
        reasons.append(contentsOf: containerFailureReasons(containerObservation))
        reasons.append(contentsOf: vitalDBFailureReasons(vitalDBObservation))
        return reasons
    }

    public static func requiresGuestComposeReconcile(
        containerObservation: RuntimeObservationInput<RuntimeContainerObservation>
    ) -> Bool {
        guard case .loaded(let observation) = containerObservation else {
            return false
        }
        return !containerFailureReasons(observation).isEmpty
    }

    private static func containerFailureReasons(
        _ input: RuntimeObservationInput<RuntimeContainerObservation>
    ) -> [RuntimeFailureReason] {
        switch input {
        case .notReported:
            return []
        case .missing:
            return [.containerObservationMissing]
        case .readFailed(let message):
            return [.containerObservationReadFailed(failureToken(message))]
        case .loaded(let observation):
            return containerFailureReasons(observation)
        }
    }

    private static func containerFailureReasons(
        _ observation: RuntimeContainerObservation
    ) -> [RuntimeFailureReason] {
        switch observation.composeServicesReadState {
        case .loaded:
            break
        case .missing:
            return [.containerObservationMissing]
        case .invalid, .stale, .readFailed:
            return [.containerObservationReadFailed(
                failureToken(observation.composeServicesReadError ?? observation.composeServicesReadState.rawValue)
            )]
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
        if RuntimeHealthClassificationPolicy.isFailingContainerHealth(service.health),
           let health = service.health {
            return normalizedState(health)
        }
        return nil
    }

    private static func vitalDBFailureReasons(
        _ input: RuntimeObservationInput<VitalDBObservationDocument>
    ) -> [RuntimeFailureReason] {
        switch input {
        case .notReported:
            return []
        case .missing:
            return [.vitalDBObservationMissing]
        case .readFailed(let message):
            return [.vitalDBObservationReadFailed(failureToken(message))]
        case .loaded(let observation):
            return vitalDBFailureReasons(observation)
        }
    }

    private static func vitalDBFailureReasons(
        _ observation: VitalDBObservationDocument
    ) -> [RuntimeFailureReason] {
        var reasons: [RuntimeFailureReason] = []
        if !observation.ready {
            reasons.append(.vitalDBAnomaly(
                kind: "observer-unhealthy",
                subject: failureToken(observation.source)
            ))
        }

        for anomaly in observation.anomalies where isRuntimeCriticalVitalDBAnomaly(anomaly) {
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

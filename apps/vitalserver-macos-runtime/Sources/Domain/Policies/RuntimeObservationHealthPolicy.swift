import Contracts
import Foundation

public enum RuntimeObservationHealthPolicy {
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

}

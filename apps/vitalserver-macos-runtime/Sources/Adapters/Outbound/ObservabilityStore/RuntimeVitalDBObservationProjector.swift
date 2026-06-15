import Contracts
import Errors

public struct RuntimeVitalDBObservationProjector {
    public let appendObservation: (VitalDBObservationDocument) throws -> Void
    public let log: (String) -> Void

    public init(
        appendObservation: @escaping (VitalDBObservationDocument) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.appendObservation = appendObservation
        self.log = log
    }

    public func project(_ observation: VitalDBObservationDocument) throws {
        try appendObservation(observation)
    }

    public func projectBestEffort(_ observation: VitalDBObservationDocument) {
        do {
            try project(observation)
        } catch {
            log(
                "vitaldb observation projection failed " +
                    "observedAt=\(observation.observedAt) error=\(error.localizedDescription)"
            )
        }
    }
}

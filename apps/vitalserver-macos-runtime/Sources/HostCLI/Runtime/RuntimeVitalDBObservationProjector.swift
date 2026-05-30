import Contracts

struct RuntimeVitalDBObservationProjector {
    let appendObservation: (VitalDBObservationDocument) throws -> Void
    let log: (String) -> Void

    func project(_ observation: VitalDBObservationDocument) throws {
        try appendObservation(observation)
    }

    func projectBestEffort(_ observation: VitalDBObservationDocument) {
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

import Contracts

struct RuntimeObservedStatusPublisher {
    let writeStatus: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeProgressDocument?
    ) throws -> RuntimeHealthSnapshot
    let projectObservation: (VitalDBObservationDocument) -> Void

    func publishStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        let snapshot = try writeStatus(status, operation, message, progress)
        if let observation = snapshot.vitalDBObservation {
            projectObservation(observation)
        }
    }
}

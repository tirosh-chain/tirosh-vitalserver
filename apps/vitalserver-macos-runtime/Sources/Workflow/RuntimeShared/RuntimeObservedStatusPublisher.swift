import Contracts

public struct RuntimeObservedStatusPublisher {
    public let writeStatus: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeProgressDocument?
    ) throws -> RuntimeHealthSnapshot
    public let projectObservation: (VitalDBObservationDocument) -> Void

    public init(
        writeStatus: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeProgressDocument?
        ) throws -> RuntimeHealthSnapshot,
        projectObservation: @escaping (VitalDBObservationDocument) -> Void
    ) {
        self.writeStatus = writeStatus
        self.projectObservation = projectObservation
    }

    public func publishStatus(
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

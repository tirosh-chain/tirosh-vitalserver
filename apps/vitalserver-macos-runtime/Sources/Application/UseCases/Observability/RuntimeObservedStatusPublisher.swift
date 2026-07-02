import Contracts

public struct RuntimeObservedStatusPublisher {
    public let writeStatus: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeProgressDocument?
    ) throws -> RuntimeHealthSnapshot

    public init(
        writeStatus: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeProgressDocument?
        ) throws -> RuntimeHealthSnapshot
    ) {
        self.writeStatus = writeStatus
    }

    public func publishStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        _ = try writeStatus(status, operation, message, progress)
    }
}

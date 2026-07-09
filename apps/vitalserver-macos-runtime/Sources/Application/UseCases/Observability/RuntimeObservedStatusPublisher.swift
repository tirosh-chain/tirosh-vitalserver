import Contracts

public struct RuntimeObservedStatusPublisher {
    public let writeStatus: (
        RuntimeStatusLevel
    ) throws -> RuntimeHealthSnapshot

    public init(
        writeStatus: @escaping (
            RuntimeStatusLevel
        ) throws -> RuntimeHealthSnapshot
    ) {
        self.writeStatus = writeStatus
    }

    public func publishStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String
    ) throws {
        _ = try writeStatus(status)
    }
}

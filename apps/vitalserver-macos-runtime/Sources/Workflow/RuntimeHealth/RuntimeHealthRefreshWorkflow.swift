import Application
import Contracts
import Errors

public struct RuntimeHealthRefreshWriter {
    public var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    public var writeStatusBestEffort: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public var recordObservedEventBestEffort: (
        RuntimeStatusLevel,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot
    ) -> Void

    public init(
        writeStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void,
        writeStatusBestEffort: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        recordObservedEventBestEffort: @escaping (
            RuntimeStatusLevel,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot
        ) -> Void
    ) {
        self.writeStatus = writeStatus
        self.writeStatusBestEffort = writeStatusBestEffort
        self.recordObservedEventBestEffort = recordObservedEventBestEffort
    }
}

public struct RuntimeHealthRefreshReader {
    public var healthSnapshot: () -> RuntimeHealthSnapshot

    public init(
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot
    ) {
        self.healthSnapshot = healthSnapshot
    }
}

public struct RuntimeHealthRefreshWorkflow {
    private let useCase: RefreshRuntimeHealthUseCase
    private let reader: RuntimeHealthRefreshReader
    private let writer: RuntimeHealthRefreshWriter

    public init(
        useCase: RefreshRuntimeHealthUseCase,
        reader: RuntimeHealthRefreshReader,
        writer: RuntimeHealthRefreshWriter
    ) {
        self.useCase = useCase
        self.reader = reader
        self.writer = writer
    }

    public func refresh() throws -> RuntimeHealthRefreshDecision {
        let decision = useCase.decision(snapshot: reader.healthSnapshot())

        guard decision.healthy else {
            writer.writeStatusBestEffort(
                decision.status,
                decision.operation,
                decision.statusMessage
            )
            if let observedEventMessage = decision.observedEventMessage {
                writer.recordObservedEventBestEffort(
                    decision.status,
                    decision.operation,
                    observedEventMessage,
                    decision.snapshot
                )
            }
            throw RuntimeHealthRefreshWorkflowError.operationFailed(decision.statusMessage)
        }

        try writer.writeStatus(decision.status, decision.operation, decision.statusMessage)
        return decision
    }
}

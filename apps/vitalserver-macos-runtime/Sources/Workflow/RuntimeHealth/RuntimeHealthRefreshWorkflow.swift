import Application
import Contracts

public enum RuntimeHealthRefreshWorkflowError: Error, Equatable, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}

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

public struct RuntimeHealthRefreshWorkflow {
    private let useCase: RefreshRuntimeHealthUseCase
    private let writer: RuntimeHealthRefreshWriter

    public init(
        useCase: RefreshRuntimeHealthUseCase,
        writer: RuntimeHealthRefreshWriter
    ) {
        self.useCase = useCase
        self.writer = writer
    }

    public func refresh() throws -> RuntimeHealthRefreshDecision {
        let decision = useCase.refresh()

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

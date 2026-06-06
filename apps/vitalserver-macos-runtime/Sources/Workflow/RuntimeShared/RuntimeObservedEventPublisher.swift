import Application
import Contracts
import Errors

public struct RuntimeObservedEventPublisher {
    public let previousStatus: () -> RuntimeStatusLevel?
    public let recordEvent: (
        RuntimeStatusLevel,
        RuntimeStatusLevel?,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) throws -> Void
    public let recordEventBestEffort: (
        RuntimeStatusLevel,
        RuntimeStatusLevel?,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) -> Void
    private var useCase: RefreshRuntimeHealthUseCase {
        RefreshRuntimeHealthUseCase()
    }

    public init(
        previousStatus: @escaping () -> RuntimeStatusLevel?,
        recordEvent: @escaping (
            RuntimeStatusLevel,
            RuntimeStatusLevel?,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot,
            RuntimeEventType
        ) throws -> Void,
        recordEventBestEffort: @escaping (
            RuntimeStatusLevel,
            RuntimeStatusLevel?,
            RuntimeOperation,
            String,
            RuntimeHealthSnapshot,
            RuntimeEventType
        ) -> Void
    ) {
        self.previousStatus = previousStatus
        self.recordEvent = recordEvent
        self.recordEventBestEffort = recordEventBestEffort
    }

    public func recordObservedEvent(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        snapshot: RuntimeHealthSnapshot,
        defaultEventType: RuntimeEventType = .statusChanged
    ) throws {
        try recordEvent(
            status,
            previousStatus(),
            operation,
            message,
            snapshot,
            useCase.observedEventType(snapshot: snapshot, defaultEventType: defaultEventType)
        )
    }

    public func recordObservedEventBestEffort(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        snapshot: RuntimeHealthSnapshot,
        defaultEventType: RuntimeEventType = .statusChanged
    ) {
        recordEventBestEffort(
            status,
            previousStatus(),
            operation,
            message,
            snapshot,
            useCase.observedEventType(snapshot: snapshot, defaultEventType: defaultEventType)
        )
    }

    public func recordObservedEventBestEffort(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        snapshot: RuntimeHealthSnapshot,
        eventType: RuntimeEventType
    ) {
        recordEventBestEffort(
            status,
            previousStatus(),
            operation,
            message,
            snapshot,
            eventType
        )
    }
}

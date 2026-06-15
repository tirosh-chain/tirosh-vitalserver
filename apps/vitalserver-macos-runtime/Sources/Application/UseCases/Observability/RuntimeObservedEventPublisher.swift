import Contracts
import Errors

public struct RuntimeObservedEventPublisher {
    public let previousStatus: () -> RuntimeStatusLevel?
    public let eventTypeForSnapshot: (RuntimeHealthSnapshot, RuntimeEventType) -> RuntimeEventType
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
        ) -> Void,
        eventTypeForSnapshot: @escaping (RuntimeHealthSnapshot, RuntimeEventType) -> RuntimeEventType = {
            _, defaultEventType in defaultEventType
        }
    ) {
        self.previousStatus = previousStatus
        self.eventTypeForSnapshot = eventTypeForSnapshot
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
            eventTypeForSnapshot(snapshot, defaultEventType)
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
            eventTypeForSnapshot(snapshot, defaultEventType)
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

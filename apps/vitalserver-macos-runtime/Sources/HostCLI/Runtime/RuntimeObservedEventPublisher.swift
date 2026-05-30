import Contracts

struct RuntimeObservedEventPublisher {
    let previousStatus: () -> RuntimeStatusLevel?
    let recordEvent: (
        RuntimeStatusLevel,
        RuntimeStatusLevel?,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) throws -> Void
    let recordEventBestEffort: (
        RuntimeStatusLevel,
        RuntimeStatusLevel?,
        RuntimeOperation,
        String,
        RuntimeHealthSnapshot,
        RuntimeEventType
    ) -> Void

    func recordObservedEvent(
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
            RuntimeObservedEventTypePolicy.eventType(for: snapshot, defaultEventType: defaultEventType)
        )
    }

    func recordObservedEventBestEffort(
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
            RuntimeObservedEventTypePolicy.eventType(for: snapshot, defaultEventType: defaultEventType)
        )
    }

    func recordObservedEventBestEffort(
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

enum RuntimeObservedEventTypePolicy {
    static func eventType(
        for snapshot: RuntimeHealthSnapshot,
        defaultEventType: RuntimeEventType = .statusChanged
    ) -> RuntimeEventType {
        if !snapshot.vmErrors.isEmpty {
            return .vmErrorObserved
        }
        if !snapshot.failureReasons.isEmpty {
            return .domainErrorObserved
        }
        return defaultEventType
    }
}

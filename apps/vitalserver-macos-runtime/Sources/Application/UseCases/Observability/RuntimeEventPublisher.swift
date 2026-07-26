import Contracts
import Errors

public struct RuntimeEventPublisher {
    public let factory: RuntimeEventFactory
    public let recorder: RuntimeObservationRecorder

    public init(
        factory: RuntimeEventFactory,
        recorder: RuntimeObservationRecorder
    ) {
        self.factory = factory
        self.recorder = recorder
    }

    public func recordObservedEvent(
        _ status: RuntimeStatusLevel,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation,
        message: String,
        healthSnapshot: RuntimeHealthSnapshot,
        eventType: RuntimeEventType = .statusChanged,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        let event = factory.observedStatusEvent(
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            healthSnapshot: healthSnapshot,
            eventType: eventType,
            progress: progress
        )
        try recorder.recordEvent(event)
    }

    public func recordObservedEventBestEffort(
        _ status: RuntimeStatusLevel,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation,
        message: String,
        healthSnapshot: RuntimeHealthSnapshot,
        eventType: RuntimeEventType = .statusChanged,
        progress: RuntimeProgressDocument? = nil
    ) {
        let event = factory.observedStatusEvent(
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            healthSnapshot: healthSnapshot,
            eventType: eventType,
            progress: progress
        )
        recorder.recordEventBestEffort(event)
    }

    public func recordDocumentEventBestEffort(
        source: String = "host-runtime",
        eventType: RuntimeEventType,
        timestamp: String? = nil,
        status: RuntimeStatusLevel? = nil,
        previousStatus: RuntimeStatusLevel? = nil,
        operation: RuntimeOperation? = nil,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) {
        let event = factory.documentEvent(
            source: source,
            eventType: eventType,
            timestamp: timestamp,
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            progress: progress
        )
        recorder.recordEventBestEffort(event)
    }

    public func recordCommandEventBestEffort(
        _ eventType: RuntimeEventType,
        executable: String,
        arguments: [String],
        result: RuntimeProcessResult?
    ) {
        let event = factory.commandEvent(
            eventType,
            executable: executable,
            arguments: arguments,
            result: result
        )
        recorder.recordEventBestEffort(event)
    }

    public func recordProgressEventBestEffort(
        status: RuntimeStatusLevel,
        message: String,
        progress: RuntimeProgressDocument
    ) {
        recordDocumentEventBestEffort(
            eventType: .progressUpdated,
            timestamp: progress.updatedAt,
            status: status,
            operation: progress.operation,
            message: message,
            progress: progress
        )
    }

    public func recordLifecycleEventBestEffort(
        operation: RuntimeOperation,
        message: String,
        eventType: RuntimeEventType
    ) {
        recordDocumentEventBestEffort(
            eventType: eventType,
            operation: operation,
            message: message,
            progress: nil
        )
    }
}

import Contracts
import Core

struct RuntimeEventPublisher {
    let factory: RuntimeEventFactory
    let recorder: RuntimeObservationRecorder

    func recordObservedEvent(
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

    func recordObservedEventBestEffort(
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

    func recordStatusDocumentEventBestEffort(
        _ statusDocument: RuntimeStatusDocument,
        operation: RuntimeOperation,
        message: String,
        eventType: RuntimeEventType,
        progress: RuntimeProgressDocument? = nil
    ) {
        let event = factory.statusDocumentEvent(
            statusDocument,
            operation: operation,
            message: message,
            eventType: eventType,
            progress: progress
        )
        recorder.recordEventBestEffort(event)
    }

    func recordDocumentEventBestEffort(
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

    func recordCommandEventBestEffort(
        _ eventType: RuntimeEventType,
        executable: String,
        arguments: [String],
        result: RuntimeProcessResult?
    ) {
        let exitSuffix = result.map { " exitCode=\($0.exitCode)" } ?? ""
        recordDocumentEventBestEffort(
            source: "host-command",
            eventType: eventType,
            message: "command \(eventType.rawValue) executable=\(executable) arguments=\(arguments.joined(separator: " "))\(exitSuffix)",
            progress: nil
        )
    }

    func recordProgressEventBestEffort(
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

    func recordLifecycleEventBestEffort(
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

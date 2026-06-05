import Contracts
import Foundation

struct RuntimeEventFactory {
    let id: () -> String
    let timestamp: () -> String
    let product: String
    let runtimeVersion: () -> String

    init(
        id: @escaping () -> String = { UUID().uuidString },
        timestamp: @escaping () -> String,
        product: String,
        runtimeVersion: @escaping () -> String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.product = product
        self.runtimeVersion = runtimeVersion
    }

    func observedStatusEvent(
        status: RuntimeStatusLevel,
        previousStatus: RuntimeStatusLevel?,
        operation: RuntimeOperation,
        message: String,
        healthSnapshot: RuntimeHealthSnapshot,
        eventType: RuntimeEventType = .statusChanged,
        progress: RuntimeProgressDocument? = nil
    ) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id(),
            eventType: eventType,
            timestamp: timestamp(),
            product: product,
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            runtimeVersion: runtimeVersion(),
            vmState: healthSnapshot.vmState,
            vmErrors: healthSnapshot.vmErrors,
            failureReasons: healthSnapshot.failureReasons,
            containerObservation: healthSnapshot.containerObservation,
            vitalDBObservation: healthSnapshot.vitalDBObservation,
            progress: progress
        )
    }

    func statusDocumentEvent(
        _ statusDocument: RuntimeStatusDocument,
        operation: RuntimeOperation,
        message: String,
        eventType: RuntimeEventType,
        progress: RuntimeProgressDocument? = nil
    ) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id(),
            eventType: eventType,
            timestamp: timestamp(),
            product: product,
            status: statusDocument.status,
            previousStatus: statusDocument.status,
            operation: operation,
            message: message,
            runtimeVersion: runtimeVersion(),
            vmState: statusDocument.vmState,
            vmErrors: statusDocument.vmErrors,
            failureReasons: statusDocument.failureReasons,
            containerObservation: statusDocument.containerObservation,
            vitalDBObservation: statusDocument.vitalDBObservation,
            progress: progress
        )
    }

    func documentEvent(
        source: String = "host-runtime",
        eventType: RuntimeEventType,
        timestamp explicitTimestamp: String? = nil,
        status: RuntimeStatusLevel? = nil,
        previousStatus: RuntimeStatusLevel? = nil,
        operation: RuntimeOperation? = nil,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id(),
            source: source,
            eventType: eventType,
            timestamp: explicitTimestamp ?? timestamp(),
            product: product,
            status: status,
            previousStatus: previousStatus,
            operation: operation,
            message: message,
            runtimeVersion: runtimeVersion(),
            failureReasons: [],
            progress: progress
        )
    }
}

import Contracts
import Foundation
import Errors

public struct RuntimeObservationRecorder {
    public let eventRepository: any RuntimeEventRecording
    public let log: (String) -> Void

    public init(
        eventRepository: any RuntimeEventRecording,
        log: @escaping (String) -> Void
    ) {
        self.eventRepository = eventRepository
        self.log = log
    }

    public func recordEvent(_ event: RuntimeEventDocument) throws {
        try eventRepository.append(event)
    }

    public func recordEventBestEffort(_ event: RuntimeEventDocument) {
        do {
            try recordEvent(event)
        } catch {
            log("observability event recording failed eventType=\(event.eventType.rawValue) error=\(error.localizedDescription)")
        }
    }
}

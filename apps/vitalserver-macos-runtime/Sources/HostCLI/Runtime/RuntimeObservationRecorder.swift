import Core
import Contracts
import Foundation

struct RuntimeObservationRecorder {
    let eventRepository: any RuntimeEventRepository
    let log: (String) -> Void

    init(
        eventRepository: any RuntimeEventRepository,
        log: @escaping (String) -> Void
    ) {
        self.eventRepository = eventRepository
        self.log = log
    }

    func recordEvent(_ event: RuntimeEventDocument) throws {
        try eventRepository.append(event)
    }

    func recordEventBestEffort(_ event: RuntimeEventDocument) {
        do {
            try recordEvent(event)
        } catch {
            log("observability event recording failed eventType=\(event.eventType.rawValue) error=\(error.localizedDescription)")
        }
    }
}

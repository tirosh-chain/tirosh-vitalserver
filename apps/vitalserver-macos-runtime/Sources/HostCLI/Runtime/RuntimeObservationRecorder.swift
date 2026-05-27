import Core
import Contracts
import Foundation
import HostInfrastructure

struct RuntimeObservationRecorder {
    let eventRepository: any RuntimeEventRepository
    let observabilityStore: SQLiteRuntimeObservabilityStore
    let log: (String) -> Void

    init(
        eventRepository: any RuntimeEventRepository,
        observabilityStore: SQLiteRuntimeObservabilityStore,
        log: @escaping (String) -> Void
    ) {
        self.eventRepository = eventRepository
        self.observabilityStore = observabilityStore
        self.log = log
    }

    func record(_ event: RuntimeEventDocument) throws {
        try eventRepository.append(event)
        if let vitalDBObservation = event.vitalDBObservation {
            try? observabilityStore.append(vitalDBObservation)
        }
    }

    func recordBestEffort(_ event: RuntimeEventDocument) {
        do {
            try record(event)
        } catch {
            log("observability event recording failed eventType=\(event.eventType.rawValue) error=\(error.localizedDescription)")
        }
    }
}

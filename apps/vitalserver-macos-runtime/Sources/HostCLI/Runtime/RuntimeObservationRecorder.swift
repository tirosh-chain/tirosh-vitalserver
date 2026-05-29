import Core
import Contracts
import Foundation
import HostInfrastructure

protocol VitalDBObservationProjectionStore {
    func append(_ observation: VitalDBObservationDocument) throws
}

extension SQLiteRuntimeObservabilityStore: VitalDBObservationProjectionStore {}

struct RuntimeObservationRecorder {
    let eventRepository: any RuntimeEventRepository
    let vitalDBObservationStore: any VitalDBObservationProjectionStore
    let log: (String) -> Void

    init(
        eventRepository: any RuntimeEventRepository,
        vitalDBObservationStore: any VitalDBObservationProjectionStore,
        log: @escaping (String) -> Void
    ) {
        self.eventRepository = eventRepository
        self.vitalDBObservationStore = vitalDBObservationStore
        self.log = log
    }

    func recordEvent(_ event: RuntimeEventDocument) throws {
        try eventRepository.append(event)
        if let vitalDBObservation = event.vitalDBObservation {
            do {
                try vitalDBObservationStore.append(vitalDBObservation)
            } catch {
                log(
                    "vitaldb observation recording failed " +
                        "eventType=\(event.eventType.rawValue) observedAt=\(vitalDBObservation.observedAt) " +
                        "error=\(error.localizedDescription)"
                )
            }
        }
    }

    func recordEventBestEffort(_ event: RuntimeEventDocument) {
        do {
            try recordEvent(event)
        } catch {
            log("observability event recording failed eventType=\(event.eventType.rawValue) error=\(error.localizedDescription)")
        }
    }
}

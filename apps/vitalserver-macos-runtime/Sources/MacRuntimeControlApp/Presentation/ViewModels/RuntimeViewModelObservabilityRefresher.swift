import Contracts
import Foundation
import RuntimeControl

@MainActor
protocol RuntimeViewModelObservabilitySnapshotLoading {
    func loadRuntimeEvents(query: RuntimeEventQuery) async -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() async -> RuntimeVitalDBObservationSnapshot
    func loadVitalRecorders() async -> RuntimeVitalRecorderHistory
    func loadVitalRelationships() async -> RuntimeVitalRelationshipHistory
}

extension RuntimeViewModelSnapshotLoader: RuntimeViewModelObservabilitySnapshotLoading {}

struct RuntimeViewModelRuntimeEventRefreshResult {
    let events: RuntimeEventHistory
    let last24HoursCount: Int
    let containerObservation: RuntimeContainerObservation?
}

struct RuntimeViewModelVitalObservabilityRefreshResult {
    let observationSnapshot: RuntimeVitalDBObservationSnapshot
    let recorders: RuntimeVitalRecorderHistory
    let relationships: RuntimeVitalRelationshipHistory
}

@MainActor
struct RuntimeViewModelObservabilityRefresher {
    private let snapshots: any RuntimeViewModelObservabilitySnapshotLoading
    private let now: () -> Date

    init(
        snapshots: any RuntimeViewModelObservabilitySnapshotLoading,
        now: @escaping () -> Date = Date.init
    ) {
        self.snapshots = snapshots
        self.now = now
    }

    func refreshRuntimeEvents(
        limit: Int,
        periodRawValue: String,
        filterRawValue: String,
        statusContainerObservation: RuntimeContainerObservation?
    ) async -> RuntimeViewModelRuntimeEventRefreshResult {
        let currentTime = now()
        let events = await snapshots.loadRuntimeEvents(
            query: RuntimeEventQuery(
                limit: limit,
                eventType: selectedEventType(filterRawValue: filterRawValue),
                since: selectedPeriod(periodRawValue: periodRawValue).sinceTimestamp(now: currentTime)
            )
        )
        let last24Hours = await snapshots.loadRuntimeEvents(
            query: RuntimeEventQuery(
                limit: 1,
                since: RuntimeEventPeriodOption.last24Hours.sinceTimestamp(now: currentTime)
            )
        )
        return RuntimeViewModelRuntimeEventRefreshResult(
            events: events,
            last24HoursCount: last24Hours.matchingCount ?? last24Hours.events.count,
            containerObservation: statusContainerObservation
                ?? events.events.first { $0.containerObservation != nil }?.containerObservation
        )
    }

    func refreshVitalObservability() async -> RuntimeViewModelVitalObservabilityRefreshResult {
        let observationSnapshot = await snapshots.loadVitalDBObservationSnapshot()
        let recorders = await snapshots.loadVitalRecorders()
        let relationships = await snapshots.loadVitalRelationships()
        return RuntimeViewModelVitalObservabilityRefreshResult(
            observationSnapshot: observationSnapshot,
            recorders: recorders,
            relationships: relationships
        )
    }

    private func selectedPeriod(periodRawValue: String) -> RuntimeEventPeriodOption {
        RuntimeEventPeriodOption(rawValue: periodRawValue) ?? .last24Hours
    }

    private func selectedEventType(filterRawValue: String) -> RuntimeEventType? {
        filterRawValue.isEmpty ? nil : RuntimeEventType(rawValue: filterRawValue)
    }
}

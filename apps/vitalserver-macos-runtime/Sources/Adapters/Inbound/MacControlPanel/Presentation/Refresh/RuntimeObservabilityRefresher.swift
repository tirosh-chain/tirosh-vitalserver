import Contracts
import Foundation
import RuntimeControl
import Errors

@MainActor
public protocol RuntimeObservabilitySnapshotLoading {
    func loadRuntimeEvents(query: RuntimeEventQuery) async -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() async -> RuntimeVitalDBObservationSnapshot
    func loadVitalRecorders() async -> RuntimeVitalRecorderHistory
    func loadVitalRelationships() async -> RuntimeVitalRelationshipHistory
}

public struct RuntimeEventRefreshResult {
    public let events: RuntimeEventHistory
    public let last24HoursCount: Int
    public let containerObservation: RuntimeContainerObservation?

    public init(
        events: RuntimeEventHistory,
        last24HoursCount: Int,
        containerObservation: RuntimeContainerObservation?
    ) {
        self.events = events
        self.last24HoursCount = last24HoursCount
        self.containerObservation = containerObservation
    }
}

public struct RuntimeVitalObservabilityRefreshResult {
    public let observationSnapshot: RuntimeVitalDBObservationSnapshot
    public let recorders: RuntimeVitalRecorderHistory
    public let relationships: RuntimeVitalRelationshipHistory

    public init(
        observationSnapshot: RuntimeVitalDBObservationSnapshot,
        recorders: RuntimeVitalRecorderHistory,
        relationships: RuntimeVitalRelationshipHistory
    ) {
        self.observationSnapshot = observationSnapshot
        self.recorders = recorders
        self.relationships = relationships
    }
}

@MainActor
public struct RuntimeObservabilityRefresher {
    private let snapshots: any RuntimeObservabilitySnapshotLoading
    private let now: () -> Date

    public init(
        snapshots: any RuntimeObservabilitySnapshotLoading,
        now: @escaping () -> Date = Date.init
    ) {
        self.snapshots = snapshots
        self.now = now
    }

    public func refreshRuntimeEvents(
        limit: Int,
        periodRawValue: String,
        filterRawValue: String,
        statusContainerObservation: RuntimeContainerObservation?
    ) async -> RuntimeEventRefreshResult {
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
        return RuntimeEventRefreshResult(
            events: events,
            last24HoursCount: last24Hours.matchingCount ?? last24Hours.events.count,
            containerObservation: statusContainerObservation
        )
    }

    public func refreshVitalObservability() async -> RuntimeVitalObservabilityRefreshResult {
        let observationSnapshot = await snapshots.loadVitalDBObservationSnapshot()
        let recorders = await snapshots.loadVitalRecorders()
        let relationships = await snapshots.loadVitalRelationships()
        return RuntimeVitalObservabilityRefreshResult(
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

extension RuntimePresentationSnapshotLoader: RuntimeObservabilitySnapshotLoading {}

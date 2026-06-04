import Contracts
import Foundation
import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

@MainActor
final class RuntimeViewModelObservabilityRefresherTests: XCTestCase {
    func testRuntimeEventRefreshBuildsSelectedQueriesAndCount() async {
        let containerObservation = runtimeContainerObservation(http: "http://event.example")
        let event = runtimeEvent(id: "event-1", containerObservation: containerObservation)
        let snapshots = StubObservabilitySnapshotLoader(
            eventResponses: [
                RuntimeEventHistory(events: [event], matchingCount: 1),
                RuntimeEventHistory(events: [], matchingCount: 42),
            ]
        )
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let refresher = RuntimeViewModelObservabilityRefresher(snapshots: snapshots, now: { now })

        let result = await refresher.refreshRuntimeEvents(
            limit: 25,
            periodRawValue: RuntimeEventPeriodOption.lastHour.rawValue,
            filterRawValue: RuntimeEventType.watchdogSkipped.rawValue,
            statusContainerObservation: nil
        )

        XCTAssertEqual(snapshots.runtimeEventQueries.count, 2)
        XCTAssertEqual(snapshots.runtimeEventQueries[0].limit, 25)
        XCTAssertEqual(snapshots.runtimeEventQueries[0].eventType, .watchdogSkipped)
        XCTAssertEqual(snapshots.runtimeEventQueries[0].since, isoTimestamp(now.addingTimeInterval(-60 * 60)))
        XCTAssertEqual(snapshots.runtimeEventQueries[1].limit, 1)
        XCTAssertNil(snapshots.runtimeEventQueries[1].eventType)
        XCTAssertEqual(snapshots.runtimeEventQueries[1].since, isoTimestamp(now.addingTimeInterval(-24 * 60 * 60)))
        XCTAssertEqual(result.events.events.map(\.id), ["event-1"])
        XCTAssertEqual(result.last24HoursCount, 42)
        XCTAssertEqual(result.containerObservation, containerObservation)
    }

    func testRuntimeEventRefreshPrefersStatusContainerObservation() async {
        let eventContainerObservation = runtimeContainerObservation(http: "http://event.example")
        let statusContainerObservation = runtimeContainerObservation(http: "http://status.example")
        let snapshots = StubObservabilitySnapshotLoader(
            eventResponses: [
                RuntimeEventHistory(events: [
                    runtimeEvent(id: "event-1", containerObservation: eventContainerObservation),
                ]),
                RuntimeEventHistory(events: []),
            ]
        )
        let refresher = RuntimeViewModelObservabilityRefresher(
            snapshots: snapshots,
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )

        let result = await refresher.refreshRuntimeEvents(
            limit: 50,
            periodRawValue: RuntimeEventPeriodOption.last24Hours.rawValue,
            filterRawValue: "",
            statusContainerObservation: statusContainerObservation
        )

        XCTAssertEqual(result.containerObservation, statusContainerObservation)
    }

    func testVitalObservabilityRefreshLoadsRecordersAndRelationships() async {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120
        )
        let observationSnapshot = RuntimeVitalDBObservationSnapshot.loaded(observation)
        let recorders = RuntimeVitalRecorderHistory(updatedAt: "2026-05-30T00:00:00Z")
        let relationships = RuntimeVitalRelationshipHistory(readError: "relationships")
        let snapshots = StubObservabilitySnapshotLoader(
            observationSnapshot: observationSnapshot,
            recorderResponse: recorders,
            relationshipResponse: relationships
        )
        let refresher = RuntimeViewModelObservabilityRefresher(snapshots: snapshots)

        let result = await refresher.refreshVitalObservability()

        XCTAssertEqual(snapshots.loadVitalDBObservationSnapshotCount, 1)
        XCTAssertEqual(snapshots.loadVitalRecordersCount, 1)
        XCTAssertEqual(snapshots.loadVitalRelationshipsCount, 1)
        XCTAssertEqual(result.observationSnapshot, observationSnapshot)
        XCTAssertEqual(result.recorders, recorders)
        XCTAssertEqual(result.relationships, relationships)
    }

    private func runtimeEvent(
        id: String,
        containerObservation: RuntimeContainerObservation? = nil
    ) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: "2026-05-30T00:00:00Z",
            product: "VitalServerHelper",
            status: .healthy,
            previousStatus: nil,
            operation: .health,
            message: "message",
            runtimeVersion: "0.1.0",
            failureReasons: [],
            containerObservation: containerObservation,
            progress: nil
        )
    }

    private func runtimeContainerObservation(http: String) -> RuntimeContainerObservation {
        RuntimeContainerObservation(
            auditProxyHTTP: http,
            auditProxyStatus: nil,
            containerLogsPresent: false,
            containerLogsBytes: nil
        )
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

@MainActor
private final class StubObservabilitySnapshotLoader: RuntimeViewModelObservabilitySnapshotLoading {
    var eventResponses: [RuntimeEventHistory]
    let observationSnapshot: RuntimeVitalDBObservationSnapshot
    let recorderResponse: RuntimeVitalRecorderHistory
    let relationshipResponse: RuntimeVitalRelationshipHistory
    private(set) var runtimeEventQueries: [RuntimeEventQuery] = []
    private(set) var loadVitalDBObservationSnapshotCount = 0
    private(set) var loadVitalRecordersCount = 0
    private(set) var loadVitalRelationshipsCount = 0

    init(
        eventResponses: [RuntimeEventHistory] = [],
        observationSnapshot: RuntimeVitalDBObservationSnapshot = .unavailable(),
        recorderResponse: RuntimeVitalRecorderHistory = RuntimeVitalRecorderHistory(),
        relationshipResponse: RuntimeVitalRelationshipHistory = RuntimeVitalRelationshipHistory()
    ) {
        self.eventResponses = eventResponses
        self.observationSnapshot = observationSnapshot
        self.recorderResponse = recorderResponse
        self.relationshipResponse = relationshipResponse
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) async -> RuntimeEventHistory {
        runtimeEventQueries.append(query)
        guard !eventResponses.isEmpty else {
            return RuntimeEventHistory(events: [])
        }
        return eventResponses.removeFirst()
    }

    func loadVitalDBObservationSnapshot() async -> RuntimeVitalDBObservationSnapshot {
        loadVitalDBObservationSnapshotCount += 1
        return observationSnapshot
    }

    func loadVitalRecorders() async -> RuntimeVitalRecorderHistory {
        loadVitalRecordersCount += 1
        return recorderResponse
    }

    func loadVitalRelationships() async -> RuntimeVitalRelationshipHistory {
        loadVitalRelationshipsCount += 1
        return relationshipResponse
    }
}

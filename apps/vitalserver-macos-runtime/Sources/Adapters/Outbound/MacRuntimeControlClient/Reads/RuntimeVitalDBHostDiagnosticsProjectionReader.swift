import Contracts
import Foundation
import RuntimeControl

enum RuntimeVitalDBHostProjectionReadMode: Equatable, Sendable {
    case disabled
    case diagnostics
}

struct RuntimeVitalDBHostDiagnosticsProjectionReader {
    let mode: RuntimeVitalDBHostProjectionReadMode
    let paths: RuntimeObservabilityPaths
    let makeVitalDBProjectionRepository: (URL) -> RuntimeVitalDBObservationProjectionReading

    init(
        mode: RuntimeVitalDBHostProjectionReadMode = .disabled,
        paths: RuntimeObservabilityPaths,
        makeVitalDBProjectionRepository: @escaping (URL) -> RuntimeVitalDBObservationProjectionReading = {
            SQLiteVitalDBObservationRepository(url: $0)
        }
    ) {
        self.mode = mode
        self.paths = paths
        self.makeVitalDBProjectionRepository = makeVitalDBProjectionRepository
    }

    func loadObservationSnapshot(
        currentObservation: RuntimeVitalDBCurrentObservationRead
    ) -> RuntimeVitalDBObservationSnapshot {
        guard mode == .diagnostics else {
            return RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
                currentObservation: currentObservation,
                projectedObservation: .loaded(nil)
            )
        }
        let reads = projectionReadCollector(
            currentObservation: currentObservation
        ).observationSnapshotReads()
        return RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
            currentObservation: reads.current,
            projectedObservation: reads.projected
        )
    }

    func recorderProjectionReads(
        includeActivityBuckets: Bool,
        currentObservation: RuntimeVitalDBCurrentObservationRead
    ) -> RuntimeVitalDBRecorderProjectionReads {
        guard mode == .diagnostics else {
            return RuntimeVitalDBRecorderProjectionReads(
                observations: .failed("host SQLite observation projection is disabled"),
                currentObservation: currentObservation,
                activityBuckets: .notLoaded
            )
        }
        return projectionReadCollector(
            currentObservation: currentObservation
        ).recorderProjectionReads(includeActivityBuckets: includeActivityBuckets)
    }

    func loadActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        guard mode == .diagnostics else {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: [],
                readError: "host SQLite activity projection is disabled"
            )
        }
        let repository = makeVitalDBProjectionRepository(
            URL(fileURLWithPath: paths.runtimeObservabilityDB)
        )
        let currentTime = Date()
        do {
            guard let bounds = try repository.loadRecorderActivityBucketBounds(
                vrcode: query.vrcode
            ) else {
                return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                    query: query,
                    bounds: nil,
                    records: []
                )
            }
            guard let recordQuery = RuntimeVitalRecorderActivityWindowAssembler.windowReadQuery(
                query: query,
                bounds: bounds,
                currentTime: currentTime
            ) else {
                return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                    query: query,
                    bounds: bounds,
                    records: [],
                    readError: "activity window query could not be built"
                )
            }
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: bounds,
                records: try repository.loadRecorderActivityBuckets(query: recordQuery),
                currentTime: currentTime
            )
        } catch {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: [],
                readError: String(describing: error)
            )
        }
    }

    func relationshipProjectionReads() -> RuntimeVitalDBRelationshipProjectionReads {
        guard mode == .diagnostics else {
            return RuntimeVitalDBRelationshipProjectionReads(
                assignments: .failed("host SQLite relationship projection is disabled"),
                events: .failed("host SQLite relationship projection is disabled")
            )
        }
        return projectionReadCollector(
            currentObservation: .unavailable()
        ).relationshipProjectionReads()
    }

    private func projectionReadCollector(
        currentObservation: RuntimeVitalDBCurrentObservationRead
    ) -> RuntimeVitalDBProjectionReadCollector {
        RuntimeVitalDBProjectionReadCollector(
            repository: makeVitalDBProjectionRepository(
                URL(fileURLWithPath: paths.runtimeObservabilityDB)
            ),
            currentObservationProvider: RuntimeVitalDBCurrentObservationProvider {
                currentObservation
            }
        )
    }
}

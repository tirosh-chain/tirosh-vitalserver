import Contracts
import Application
import Foundation
import RuntimeControl

protocol RuntimeObservabilityReading: Sendable {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory
    func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory
    func loadVitalDBRecorderActivityWindow(query: RuntimeVitalRecorderActivityWindowQuery) -> RuntimeVitalRecorderActivityWindow
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory
}

extension RuntimeObservabilityReading {
    func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory {
        loadVitalDBRecorders()
    }

    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: nil,
            records: [],
            readError: "recorder activity window reader is unavailable"
        )
    }
}

struct SystemRuntimeObservabilityReader: RuntimeObservabilityReading, @unchecked Sendable {
    let paths: RuntimePaths
    private let fileStore: RuntimeFileStore
    private let currentObservationProvider: RuntimeVitalDBCurrentObservationProvider
    private let makeVitalDBProjectionRepository: (URL) -> RuntimeVitalDBObservationProjectionReading

    init(
        paths: RuntimePaths,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        currentObservationProvider: RuntimeVitalDBCurrentObservationProvider,
        makeVitalDBProjectionRepository: @escaping (URL) -> RuntimeVitalDBObservationProjectionReading = {
            SQLiteVitalDBObservationRepository(url: $0)
        }
    ) {
        self.paths = paths
        self.fileStore = fileStore
        self.currentObservationProvider = currentObservationProvider
        self.makeVitalDBProjectionRepository = makeVitalDBProjectionRepository
    }

    static func live(
        paths: RuntimePaths,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) -> SystemRuntimeObservabilityReader {
        SystemRuntimeObservabilityReader(
            paths: paths,
            fileStore: fileStore,
            currentObservationProvider: .live(paths: paths, fileStore: fileStore)
        )
    }

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        loadRuntimeEvents(query: RuntimeEventQuery(limit: limit))
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        let primary = JSONLRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeEvents), fileStore: fileStore)
        let secondary = SQLiteRuntimeEventRepository(url: URL(fileURLWithPath: paths.runtimeObservabilityDB))
        let repository = CompositeRuntimeEventRepository(primary: primary, secondary: secondary)
        let page = repository.query(query)
        return RuntimeEventHistory(
            events: page.events,
            nextCursor: page.nextCursor.map(RuntimeEventCursorWireCodec.encode),
            matchingCount: page.matchingCount,
            state: page.state,
            readError: page.readError
        )
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        let reads = vitalDBProjectionReadCollector().observationSnapshotReads()
        return RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
            currentObservation: reads.current,
            projectedObservation: reads.projected
        )
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        return RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: vitalDBProjectionReadCollector().recorderProjectionReads(),
            containerObservation: loadContainerObservation()
        )
    }

    func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory {
        return RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: vitalDBProjectionReadCollector().recorderProjectionReads(includeActivityBuckets: false),
            containerObservation: loadContainerObservation()
        )
    }

    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        if let validationError = query.validationError {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: [],
                readError: validationError
            )
        }
        let repository = makeVitalDBProjectionRepository(URL(fileURLWithPath: paths.runtimeObservabilityDB))
        do {
            guard let bounds = try repository.loadRecorderActivityBucketBounds(vrcode: query.vrcode) else {
                return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                    query: query,
                    bounds: nil,
                    records: []
                )
            }
            guard let recordQuery = RuntimeVitalRecorderActivityWindowAssembler.windowReadQuery(
                query: query,
                bounds: bounds
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
                records: try repository.loadRecorderActivityBuckets(query: recordQuery)
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

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        return RuntimeVitalDBRelationshipHistoryAssembler.makeHistory(
            reads: vitalDBProjectionReadCollector().relationshipProjectionReads()
        )
    }

    private func vitalDBProjectionReadCollector() -> RuntimeVitalDBProjectionReadCollector {
        RuntimeVitalDBProjectionReadCollector(
            repository: makeVitalDBProjectionRepository(URL(fileURLWithPath: paths.runtimeObservabilityDB)),
            currentObservationProvider: currentObservationProvider
        )
    }

    private func loadContainerObservation() -> RuntimeContainerObservation? {
        switch JSONFileRuntimeStatusRepository(
            url: URL(fileURLWithPath: paths.runtimeStatus),
            fileStore: fileStore
        ).loadResult() {
        case .loaded(let document):
            return document.containerObservation
        case .missing, .failed:
            return nil
        }
    }

}

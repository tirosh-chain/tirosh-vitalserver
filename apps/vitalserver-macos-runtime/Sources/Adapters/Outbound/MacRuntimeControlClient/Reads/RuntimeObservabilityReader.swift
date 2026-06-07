import Contracts
import Application
import Foundation
import RuntimeControl

protocol RuntimeObservabilityReading: Sendable {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory
}

extension RuntimeObservabilityReading {
    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        loadVitalDBObservationSnapshot().observation
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

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        loadVitalDBObservationSnapshot().observation
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
            reads: vitalDBProjectionReadCollector().recorderProjectionReads()
        )
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

}

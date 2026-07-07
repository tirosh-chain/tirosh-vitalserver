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

protocol RuntimeRecorderIngressStatusReadProviding: Sendable {
    func loadRecorderIngressStatusRead() -> RuntimeRecorderIngressStatusReadResult?
}

struct RuntimeRecorderIngressGuestStatusReadProvider: RuntimeRecorderIngressStatusReadProviding, @unchecked Sendable {
    private let guestControlBaseURL: @Sendable () -> String?
    private let guestControlGateway: @Sendable (String) throws -> any RuntimeGuestControlGateway

    init(
        guestControlBaseURL: @escaping @Sendable () -> String? = {
            RuntimeControlClientConstants.Product.localGuestControlAPIBaseURL
        },
        guestControlGateway: @escaping @Sendable (String) throws -> any RuntimeGuestControlGateway = {
            try HTTPRuntimeGuestControlGateway(
                baseURL: $0,
                timeout: RuntimeControlClientConstants.Product.guestControlAPIStatusReadTimeoutSeconds
            )
        }
    ) {
        self.guestControlBaseURL = guestControlBaseURL
        self.guestControlGateway = guestControlGateway
    }

    func loadRecorderIngressStatusRead() -> RuntimeRecorderIngressStatusReadResult? {
        guard let baseURL = guestControlBaseURL()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            return RuntimeRecorderIngressStatusReadResult(
                readState: .readFailed,
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "guestControl=baseURLUnavailable"
            )
        }

        do {
            return try guestControlGateway(baseURL).recorderIngressStatus()
        } catch {
            return RuntimeRecorderIngressStatusReadResult(
                readState: .readFailed,
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "guestControl=\(error)"
            )
        }
    }
}

struct SystemRuntimeObservabilityReader: RuntimeObservabilityReading, @unchecked Sendable {
    let paths: RuntimePaths
    private let fileStore: RuntimeFileStore
    private let currentObservationProvider: RuntimeVitalDBCurrentObservationProvider
    private let guestVitalDBReadModelProvider: RuntimeVitalDBGuestReadModelProvider?
    private let guestVitalDBActivityProvider: RuntimeVitalDBGuestActivityProvider?
    private let guestVitalDBRelationshipProvider: RuntimeVitalDBGuestRelationshipProvider?
    private let recorderIngressStatusReadProvider: (any RuntimeRecorderIngressStatusReadProviding)?

    init(
        paths: RuntimePaths,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        currentObservationProvider: RuntimeVitalDBCurrentObservationProvider,
        guestVitalDBReadModelProvider: RuntimeVitalDBGuestReadModelProvider? = nil,
        guestVitalDBActivityProvider: RuntimeVitalDBGuestActivityProvider? = nil,
        guestVitalDBRelationshipProvider: RuntimeVitalDBGuestRelationshipProvider? = nil,
        recorderIngressStatusReadProvider: (any RuntimeRecorderIngressStatusReadProviding)? = nil
    ) {
        self.paths = paths
        self.fileStore = fileStore
        self.currentObservationProvider = currentObservationProvider
        self.guestVitalDBReadModelProvider = guestVitalDBReadModelProvider
        self.guestVitalDBActivityProvider = guestVitalDBActivityProvider
        self.guestVitalDBRelationshipProvider = guestVitalDBRelationshipProvider
        self.recorderIngressStatusReadProvider = recorderIngressStatusReadProvider
    }

    static func live(
        paths: RuntimePaths,
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) -> SystemRuntimeObservabilityReader {
        SystemRuntimeObservabilityReader(
            paths: paths,
            fileStore: fileStore,
            currentObservationProvider: .live(paths: paths, fileStore: fileStore),
            guestVitalDBReadModelProvider: .live(),
            guestVitalDBActivityProvider: .live(),
            guestVitalDBRelationshipProvider: .live(),
            recorderIngressStatusReadProvider: RuntimeRecorderIngressGuestStatusReadProvider()
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
        RuntimeVitalDBObservationSnapshotAssembler.makeSnapshot(
            currentObservation: currentObservationProvider.load(),
            projectedObservation: .loaded(nil)
        )
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        return RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: recorderProjectionReads(includeActivityBuckets: true),
            recorderIngressStatusRead: recorderIngressStatusReadProvider?.loadRecorderIngressStatusRead(),
            statusEvaluationTime: currentTimestamp()
        )
    }

    func loadVitalDBRecorderSummaries() -> RuntimeVitalRecorderHistory {
        return RuntimeVitalDBRecorderHistoryAssembler.makeHistory(
            reads: recorderProjectionReads(includeActivityBuckets: false),
            recorderIngressStatusRead: recorderIngressStatusReadProvider?.loadRecorderIngressStatusRead(),
            statusEvaluationTime: currentTimestamp()
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
        if let guestVitalDBActivityProvider {
            return guestActivityWindow(
                query: query,
                provider: guestVitalDBActivityProvider
            )
        }
        return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: nil,
            records: [],
            readError: "Guest VitalDB activity read model is unavailable."
        )
    }

    private func guestActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery,
        provider: RuntimeVitalDBGuestActivityProvider
    ) -> RuntimeVitalRecorderActivityWindow {
        let vrcode = query.vrcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vrcode.isEmpty else {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: [],
                readError: "recorder activity window requires vrcode"
            )
        }
        let read = provider.load(vrcode: vrcode)
        guard read.state == .loaded else {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: [],
                readError: read.readError ?? "guestControl.activity=\(read.state.rawValue)"
            )
        }
        if let readVrcode = read.vrcode, readVrcode != vrcode {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: [],
                readError: "guestControl.activity returned vrcode=\(readVrcode) for requested vrcode=\(vrcode)"
            )
        }
        let records = read.buckets
        guard records.allSatisfy({ $0.vrcode == vrcode }) else {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: [],
                readError: "guestControl.activity returned buckets for a different recorder"
            )
        }
        guard let bounds = guestActivityBounds(vrcode: vrcode, records: records) else {
            return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
                query: query,
                bounds: nil,
                records: []
            )
        }
        guard let recordQuery = RuntimeVitalRecorderActivityWindowAssembler.windowReadQuery(
            query: query,
            bounds: bounds,
            currentTime: Date()
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
            records: records.filter { record in
                activityRecord(record, isIncludedIn: recordQuery)
            }
        )
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        if let guestVitalDBRelationshipProvider {
            return guestVitalDBRelationshipProvider.load()
        }
        return .failed(
            readError: "Guest VitalDB relationship read model is unavailable."
        )
    }

    private func recorderProjectionReads(includeActivityBuckets: Bool) -> RuntimeVitalDBRecorderProjectionReads {
        if let guestRead = guestVitalDBReadModelProvider?.load() {
            return RuntimeVitalDBRecorderProjectionReads(
                observations: .loaded([]),
                currentObservation: guestRead,
                activityBuckets: .notLoaded
            )
        }
        return RuntimeVitalDBRecorderProjectionReads(
            observations: .loaded([]),
            currentObservation: .unavailable(readIssues: ["guestControl=readModelProviderUnavailable"]),
            activityBuckets: .notLoaded
        )
    }

    private func currentTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private func guestActivityBounds(
    vrcode: String,
    records: [VitalDBRecorderActivityBucketRecord]
) -> VitalDBRecorderActivityBucketBounds? {
    let starts = records.map(\.bucketStartedAt).sorted()
    guard let first = starts.first, let latest = starts.last else {
        return nil
    }
    return VitalDBRecorderActivityBucketBounds(
        vrcode: vrcode,
        firstBucketStartedAt: first,
        latestBucketStartedAt: latest
    )
}

private func activityRecord(
    _ record: VitalDBRecorderActivityBucketRecord,
    isIncludedIn query: VitalDBRecorderActivityBucketQuery
) -> Bool {
    guard query.vrcode == nil || query.vrcode == record.vrcode else {
        return false
    }
    if let since = query.since, record.bucketStartedAt < since {
        return false
    }
    if let until = query.until, record.bucketStartedAt > until {
        return false
    }
    return true
}

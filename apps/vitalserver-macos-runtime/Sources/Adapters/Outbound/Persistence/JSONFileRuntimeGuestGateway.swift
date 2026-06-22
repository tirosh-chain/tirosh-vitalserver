import Foundation
import Application
import Contracts
import Errors

public struct JSONFileRuntimeGuestGateway: RuntimeGuestGateway {
    public let runtimeStateURL: URL
    public let bootstrapResultURL: URL
    public let updateActivationRequestURL: URL
    public let updateActivationResultURL: URL
    public let updateShutdownRequestURL: URL
    public let updateShutdownResultURL: URL
    public let datastoreRepairRequestURL: URL
    public let datastoreRepairResultURL: URL
    public let guestComposeReconcileRequestURL: URL
    public let guestComposeReconcileResultURL: URL
    public let redisRestoreRequestURL: URL
    public let redisRestoreResultURL: URL
    private let fileStore: RuntimeFileReading & RuntimeFileWriting

    public init(
        runtimeStateURL: URL,
        bootstrapResultURL: URL,
        updateActivationRequestURL: URL,
        updateActivationResultURL: URL,
        updateShutdownRequestURL: URL,
        updateShutdownResultURL: URL,
        datastoreRepairRequestURL: URL,
        datastoreRepairResultURL: URL,
        guestComposeReconcileRequestURL: URL,
        guestComposeReconcileResultURL: URL,
        redisRestoreRequestURL: URL,
        redisRestoreResultURL: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.runtimeStateURL = runtimeStateURL
        self.bootstrapResultURL = bootstrapResultURL
        self.updateActivationRequestURL = updateActivationRequestURL
        self.updateActivationResultURL = updateActivationResultURL
        self.updateShutdownRequestURL = updateShutdownRequestURL
        self.updateShutdownResultURL = updateShutdownResultURL
        self.datastoreRepairRequestURL = datastoreRepairRequestURL
        self.datastoreRepairResultURL = datastoreRepairResultURL
        self.guestComposeReconcileRequestURL = guestComposeReconcileRequestURL
        self.guestComposeReconcileResultURL = guestComposeReconcileResultURL
        self.redisRestoreRequestURL = redisRestoreRequestURL
        self.redisRestoreResultURL = redisRestoreResultURL
        self.fileStore = fileStore
    }

    public func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument> {
        decode(GuestRuntimeStateDocument.self, from: runtimeStateURL)
    }

    public func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> {
        decode(GuestBootstrapResultDocument.self, from: bootstrapResultURL)
    }

    public func removeUpdateActivationResult() throws {
        try removeFileIfPresent(updateActivationResultURL)
    }

    public func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {
        try write(
            GuestUpdateActivationRequestDocument(
                requestId: request.id,
                requestedAt: request.requestedAt,
                version: request.version
            ),
            to: updateActivationRequestURL
        )
    }

    public func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument> {
        decode(GuestUpdateActivationResultDocument.self, from: updateActivationResultURL)
    }

    public func removeUpdateShutdownResult() throws {
        try removeFileIfPresent(updateShutdownResultURL)
    }

    public func clearUpdateShutdownPreparation() throws {
        try removeFileIfPresent(updateShutdownRequestURL)
        try removeFileIfPresent(updateShutdownResultURL)
    }

    public func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {
        try write(
            GuestUpdateShutdownRequestDocument(
                requestId: request.id,
                requestedAt: request.requestedAt,
                version: request.version
            ),
            to: updateShutdownRequestURL
        )
    }

    public func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> {
        decode(GuestUpdateShutdownResultDocument.self, from: updateShutdownResultURL)
    }

    public func removeDatastoreRepairResult() throws {
        try removeFileIfPresent(datastoreRepairResultURL)
    }

    public func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {
        try write(
            DatastoreRepairRequestDocument(
                requestId: request.id,
                requestedAt: request.requestedAt
            ),
            to: datastoreRepairRequestURL
        )
    }

    public func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> {
        decode(DatastoreRepairResultDocument.self, from: datastoreRepairResultURL)
    }

    public func removeGuestComposeReconcileResult() throws {
        try removeFileIfPresent(guestComposeReconcileResultURL)
    }

    public func writeGuestComposeReconcileRequest(_ request: RuntimeGuestComposeReconcileRequest) throws {
        try write(
            GuestComposeReconcileRequestDocument(
                requestId: request.id,
                requestedAt: request.requestedAt
            ),
            to: guestComposeReconcileRequestURL
        )
    }

    public func loadGuestComposeReconcileResultDocument() -> RuntimeGuestDocumentLoadResult<GuestComposeReconcileResultDocument> {
        decode(GuestComposeReconcileResultDocument.self, from: guestComposeReconcileResultURL)
    }

    public func removeRedisRestoreResult() throws {
        try removeFileIfPresent(redisRestoreResultURL)
    }

    public func writeRedisRestoreRequest(_ request: RedisRestoreRequestDocument) throws {
        try write(request, to: redisRestoreRequestURL)
    }

    public func loadRedisRestoreResultDocument() -> RuntimeGuestDocumentLoadResult<RedisRestoreResultDocument> {
        decode(RedisRestoreResultDocument.self, from: redisRestoreResultURL)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> RuntimeGuestDocumentLoadResult<T> {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("runtime guest document path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("runtime guest document path state is unexpected path=\(url.path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(type, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func write<T: Encodable>(_ document: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(data, to: url, options: .atomic)
    }

    private func removeFileIfPresent(_ url: URL) throws {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            try fileStore.removeItem(at: url)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw JSONFileRuntimeGuestGatewayError.pathInspectionFailed(path: url.path, reason: reason)
        case .directory, .other, .unknown:
            throw JSONFileRuntimeGuestGatewayError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
    }
}

private struct DatastoreRepairRequestDocument: Encodable {
    let schemaVersion = 2
    let requestId: String
    let requestedAt: String
    let operation = "repair-datastore"
}

private struct GuestComposeReconcileRequestDocument: Encodable {
    let schemaVersion = 1
    let requestId: String
    let requestedAt: String
    let operation = "reconcile-compose"
}

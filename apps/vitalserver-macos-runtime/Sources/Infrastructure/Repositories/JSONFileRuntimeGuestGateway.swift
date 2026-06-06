import Foundation
import Application
import Contracts

public struct JSONFileRuntimeGuestGateway: RuntimeGuestGateway {
    public let runtimeStateURL: URL
    public let bootstrapResultURL: URL
    public let updateActivationRequestURL: URL
    public let updateActivationResultURL: URL
    public let updateShutdownRequestURL: URL
    public let updateShutdownResultURL: URL
    public let datastoreRepairRequestURL: URL
    public let datastoreRepairResultURL: URL

    public init(
        runtimeStateURL: URL,
        bootstrapResultURL: URL,
        updateActivationRequestURL: URL,
        updateActivationResultURL: URL,
        updateShutdownRequestURL: URL,
        updateShutdownResultURL: URL,
        datastoreRepairRequestURL: URL,
        datastoreRepairResultURL: URL
    ) {
        self.runtimeStateURL = runtimeStateURL
        self.bootstrapResultURL = bootstrapResultURL
        self.updateActivationRequestURL = updateActivationRequestURL
        self.updateActivationResultURL = updateActivationResultURL
        self.updateShutdownRequestURL = updateShutdownRequestURL
        self.updateShutdownResultURL = updateShutdownResultURL
        self.datastoreRepairRequestURL = datastoreRepairRequestURL
        self.datastoreRepairResultURL = datastoreRepairResultURL
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

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> RuntimeGuestDocumentLoadResult<T> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        do {
            let data = try Data(contentsOf: url)
            return try .loaded(JSONDecoder().decode(type, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func write<T: Encodable>(_ document: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func removeFileIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}

private struct DatastoreRepairRequestDocument: Encodable {
    let schemaVersion = 2
    let requestId: String
    let requestedAt: String
    let operation = "repair-datastore"
}

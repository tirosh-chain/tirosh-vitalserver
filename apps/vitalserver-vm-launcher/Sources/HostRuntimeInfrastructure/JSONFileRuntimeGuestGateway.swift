import Foundation
import RuntimeCore

public struct JSONFileRuntimeGuestGateway: RuntimeGuestGateway {
    public let runtimeStateURL: URL
    public let bootstrapResultURL: URL
    public let updateActivationRequestURL: URL
    public let updateActivationResultURL: URL
    public let datastoreRepairRequestURL: URL
    public let datastoreRepairResultURL: URL

    public init(
        runtimeStateURL: URL,
        bootstrapResultURL: URL,
        updateActivationRequestURL: URL,
        updateActivationResultURL: URL,
        datastoreRepairRequestURL: URL,
        datastoreRepairResultURL: URL
    ) {
        self.runtimeStateURL = runtimeStateURL
        self.bootstrapResultURL = bootstrapResultURL
        self.updateActivationRequestURL = updateActivationRequestURL
        self.updateActivationResultURL = updateActivationResultURL
        self.datastoreRepairRequestURL = datastoreRepairRequestURL
        self.datastoreRepairResultURL = datastoreRepairResultURL
    }

    public func loadRuntimeState() -> GuestRuntimeStateDocument? {
        decode(GuestRuntimeStateDocument.self, from: runtimeStateURL)
    }

    public func loadBootstrapResult() -> GuestBootstrapResultDocument? {
        decode(GuestBootstrapResultDocument.self, from: bootstrapResultURL)
    }

    public func removeUpdateActivationResult() throws {
        try removeFileIfPresent(updateActivationResultURL)
    }

    public func writeUpdateActivationRequest(requestId: String, requestedAt: String, version: String) throws {
        try write(
            GuestUpdateActivationRequestDocument(
                requestId: requestId,
                requestedAt: requestedAt,
                version: version
            ),
            to: updateActivationRequestURL
        )
    }

    public func loadUpdateActivationResult() -> GuestUpdateActivationResultDocument? {
        decode(GuestUpdateActivationResultDocument.self, from: updateActivationResultURL)
    }

    public func removeDatastoreRepairResult() throws {
        try removeFileIfPresent(datastoreRepairResultURL)
    }

    public func writeDatastoreRepairRequest(requestId: String, requestedAt: String) throws {
        try write(
            DatastoreRepairRequestDocument(
                requestId: requestId,
                requestedAt: requestedAt
            ),
            to: datastoreRepairRequestURL
        )
    }

    public func loadDatastoreRepairResult() -> DatastoreRepairResultDocument? {
        decode(DatastoreRepairResultDocument.self, from: datastoreRepairResultURL)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
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

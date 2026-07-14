import Contracts

public struct RuntimeEndpointStateRecord: Codable, Equatable, Sendable {
    public let runID: String
    public let lifecycleRevision: Int
    public let address: String
    public let source: RuntimeGuestAddressSource
    public let observedAt: String
    public let revision: Int

    public init(
        runID: String,
        lifecycleRevision: Int,
        address: String,
        source: RuntimeGuestAddressSource,
        observedAt: String,
        revision: Int
    ) {
        self.runID = runID
        self.lifecycleRevision = lifecycleRevision
        self.address = address
        self.source = source
        self.observedAt = observedAt
        self.revision = revision
    }
}

public struct RuntimeEndpointStateMutation: Equatable, Sendable {
    public let runID: String
    public let lifecycleRevision: Int
    public let address: String
    public let source: RuntimeGuestAddressSource
    public let observedAt: String
    public let expectedRevision: Int?

    public init(
        runID: String,
        lifecycleRevision: Int,
        address: String,
        source: RuntimeGuestAddressSource,
        observedAt: String,
        expectedRevision: Int?
    ) {
        self.runID = runID
        self.lifecycleRevision = lifecycleRevision
        self.address = address
        self.source = source
        self.observedAt = observedAt
        self.expectedRevision = expectedRevision
    }
}

public enum RuntimeEndpointStateReadResult: Equatable, Sendable {
    case missing
    case loaded(RuntimeEndpointStateRecord)
    case stale(RuntimeEndpointStateRecord, reason: String)
    case failed(String)
}

public protocol RuntimeEndpointStateReading: Sendable {
    func loadRuntimeEndpointState() -> RuntimeEndpointStateReadResult
}

public protocol RuntimeEndpointStateMutating: Sendable {
    @discardableResult
    func saveRuntimeEndpointState(
        _ mutation: RuntimeEndpointStateMutation
    ) throws -> RuntimeEndpointStateRecord
}

public protocol RuntimeEndpointStateRepository:
    RuntimeEndpointStateReading,
    RuntimeEndpointStateMutating
{}

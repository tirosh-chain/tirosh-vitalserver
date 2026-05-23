public struct RuntimeGuestActivationRequest: Equatable, Sendable {
    public let id: String
    public let requestedAt: String
    public let version: String

    public init(id: String, requestedAt: String, version: String) {
        self.id = id
        self.requestedAt = requestedAt
        self.version = version
    }
}

public struct RuntimeDatastoreRepairRequest: Equatable, Sendable {
    public let id: String
    public let requestedAt: String

    public init(id: String, requestedAt: String) {
        self.id = id
        self.requestedAt = requestedAt
    }
}

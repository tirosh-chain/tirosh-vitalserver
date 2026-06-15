public struct RuntimeHostTimeDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let epochSeconds: Int64
    public let updatedAt: String

    public init(
        schemaVersion: Int = 1,
        epochSeconds: Int64,
        updatedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.epochSeconds = epochSeconds
        self.updatedAt = updatedAt
    }
}

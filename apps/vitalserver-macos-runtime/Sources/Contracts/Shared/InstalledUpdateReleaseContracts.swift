public struct InstalledUpdateRelease: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let productId: String
    public let productVersion: String
    public let runtimeVersion: String
    public let updateId: String
    public let journalId: String
    public let journalRevision: Int
    public let reportRelativePath: String
    public let reportSHA256: String
    public let settledAt: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case productId
        case productVersion
        case runtimeVersion
        case updateId
        case journalId
        case journalRevision
        case reportRelativePath
        case reportSHA256
        case settledAt
    }

    public init(
        schemaVersion: String,
        productId: String,
        productVersion: String,
        runtimeVersion: String,
        updateId: String,
        journalId: String,
        journalRevision: Int,
        reportRelativePath: String,
        reportSHA256: String,
        settledAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.productId = productId
        self.productVersion = productVersion
        self.runtimeVersion = runtimeVersion
        self.updateId = updateId
        self.journalId = journalId
        self.journalRevision = journalRevision
        self.reportRelativePath = reportRelativePath
        self.reportSHA256 = reportSHA256
        self.settledAt = settledAt
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "InstalledUpdateRelease"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(
                String.self,
                forKey: .schemaVersion
            ),
            productId: try container.decode(String.self, forKey: .productId),
            productVersion: try container.decode(
                String.self,
                forKey: .productVersion
            ),
            runtimeVersion: try container.decode(
                String.self,
                forKey: .runtimeVersion
            ),
            updateId: try container.decode(String.self, forKey: .updateId),
            journalId: try container.decode(String.self, forKey: .journalId),
            journalRevision: try container.decode(
                Int.self,
                forKey: .journalRevision
            ),
            reportRelativePath: try container.decode(
                String.self,
                forKey: .reportRelativePath
            ),
            reportSHA256: try container.decode(
                String.self,
                forKey: .reportSHA256
            ),
            settledAt: try container.decode(String.self, forKey: .settledAt)
        )
    }
}

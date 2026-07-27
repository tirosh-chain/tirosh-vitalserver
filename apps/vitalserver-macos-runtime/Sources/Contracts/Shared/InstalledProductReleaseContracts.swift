public enum InstalledProductReleaseSource: String, Codable, Equatable, Sendable {
    case packageInstall = "package-install"
    case update
}

public struct InstalledProductRelease: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let productId: String
    public let productVersion: String
    public let runtimeVersion: String
    public let releaseRevision: Int
    public let source: InstalledProductReleaseSource
    public let installOperationId: String?
    public let updateId: String?
    public let journalId: String?
    public let journalRevision: Int?
    public let reportRelativePath: String?
    public let reportSHA256: String?
    public let settledAt: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case productId
        case productVersion
        case runtimeVersion
        case releaseRevision
        case source
        case installOperationId
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
        releaseRevision: Int,
        source: InstalledProductReleaseSource,
        installOperationId: String?,
        updateId: String?,
        journalId: String?,
        journalRevision: Int?,
        reportRelativePath: String?,
        reportSHA256: String?,
        settledAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.productId = productId
        self.productVersion = productVersion
        self.runtimeVersion = runtimeVersion
        self.releaseRevision = releaseRevision
        self.source = source
        self.installOperationId = installOperationId
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
            type: "InstalledProductRelease"
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
            releaseRevision: try container.decode(
                Int.self,
                forKey: .releaseRevision
            ),
            source: try container.decode(
                InstalledProductReleaseSource.self,
                forKey: .source
            ),
            installOperationId: try container.decodeIfPresent(
                String.self,
                forKey: .installOperationId
            ),
            updateId: try container.decodeIfPresent(
                String.self,
                forKey: .updateId
            ),
            journalId: try container.decodeIfPresent(
                String.self,
                forKey: .journalId
            ),
            journalRevision: try container.decodeIfPresent(
                Int.self,
                forKey: .journalRevision
            ),
            reportRelativePath: try container.decodeIfPresent(
                String.self,
                forKey: .reportRelativePath
            ),
            reportSHA256: try container.decodeIfPresent(
                String.self,
                forKey: .reportSHA256
            ),
            settledAt: try container.decode(String.self, forKey: .settledAt)
        )
    }
}

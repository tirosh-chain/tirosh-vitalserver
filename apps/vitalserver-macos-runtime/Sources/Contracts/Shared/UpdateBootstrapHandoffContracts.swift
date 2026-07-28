import Foundation

public struct UpdateBootstrapHandoffInvocation: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let updateId: String
    public let operationId: String
    public let requestId: String
    public let bootstrapEnvelopeId: String
    public let bootstrapSignedSHA256: String
    public let updateSpecificationSHA256: String
    public let layerOrder: [UpdateLayer]
    public let expectedJournalRevision: Int
    public let updaterRelativePath: String
    public let specificationRelativePath: String
    public let completionReceiptRelativePath: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case updateId
        case operationId
        case requestId
        case bootstrapEnvelopeId
        case bootstrapSignedSHA256
        case updateSpecificationSHA256
        case layerOrder
        case expectedJournalRevision
        case updaterRelativePath
        case specificationRelativePath
        case completionReceiptRelativePath
    }

    public init(
        schemaVersion: String,
        updateId: String,
        operationId: String,
        requestId: String,
        bootstrapEnvelopeId: String,
        bootstrapSignedSHA256: String,
        updateSpecificationSHA256: String,
        layerOrder: [UpdateLayer],
        expectedJournalRevision: Int,
        updaterRelativePath: String,
        specificationRelativePath: String,
        completionReceiptRelativePath: String
    ) {
        self.schemaVersion = schemaVersion
        self.updateId = updateId
        self.operationId = operationId
        self.requestId = requestId
        self.bootstrapEnvelopeId = bootstrapEnvelopeId
        self.bootstrapSignedSHA256 = bootstrapSignedSHA256
        self.updateSpecificationSHA256 = updateSpecificationSHA256
        self.layerOrder = layerOrder
        self.expectedJournalRevision = expectedJournalRevision
        self.updaterRelativePath = updaterRelativePath
        self.specificationRelativePath = specificationRelativePath
        self.completionReceiptRelativePath = completionReceiptRelativePath
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownUpdateBootstrapKeys(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            type: "UpdateBootstrapHandoffInvocation"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(String.self, forKey: .schemaVersion),
            updateId: try container.decode(String.self, forKey: .updateId),
            operationId: try container.decode(String.self, forKey: .operationId),
            requestId: try container.decode(String.self, forKey: .requestId),
            bootstrapEnvelopeId: try container.decode(
                String.self,
                forKey: .bootstrapEnvelopeId
            ),
            bootstrapSignedSHA256: try container.decode(
                String.self,
                forKey: .bootstrapSignedSHA256
            ),
            updateSpecificationSHA256: try container.decode(
                String.self,
                forKey: .updateSpecificationSHA256
            ),
            layerOrder: try container.decode(
                [UpdateLayer].self,
                forKey: .layerOrder
            ),
            expectedJournalRevision: try container.decode(
                Int.self,
                forKey: .expectedJournalRevision
            ),
            updaterRelativePath: try container.decode(
                String.self,
                forKey: .updaterRelativePath
            ),
            specificationRelativePath: try container.decode(
                String.self,
                forKey: .specificationRelativePath
            ),
            completionReceiptRelativePath: try container.decode(
                String.self,
                forKey: .completionReceiptRelativePath
            )
        )
    }
}

public struct WrittenUpdateBootstrapHandoffInvocation: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

import Foundation

public enum RuntimeRecorderObservabilityExpectationAction: String, Codable, Equatable, Sendable {
    case set
    case clear
}

public enum RuntimeRecorderObservabilityExpectationSource: String, Codable, Equatable, Sendable {
    case deploymentAssignment = "deployment_assignment"
    case versionCatalog = "version_catalog"
    case manual
}

public struct RuntimeRecorderObservabilityExpectationCommand: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case commandId
        case vrcode
        case expectedRevision
        case action
        case supportState
        case source
        case recorderVersion
        case producerVersion
        case protocolVersion
        case catalogRevision
        case expectedSince
        case evidenceDocument
        case decidedAt
    }

    public let commandId: String
    public let vrcode: String
    public let expectedRevision: Int
    public let action: RuntimeRecorderObservabilityExpectationAction
    public let supportState: String?
    public let source: RuntimeRecorderObservabilityExpectationSource?
    public let recorderVersion: String?
    public let producerVersion: String?
    public let protocolVersion: String?
    public let catalogRevision: String?
    public let expectedSince: String?
    public let evidenceDocument: [String: RuntimeJSONValue]
    public let decidedAt: String

    public init(
        commandId: String,
        vrcode: String,
        expectedRevision: Int,
        action: RuntimeRecorderObservabilityExpectationAction,
        supportState: String?,
        source: RuntimeRecorderObservabilityExpectationSource?,
        recorderVersion: String?,
        producerVersion: String?,
        protocolVersion: String?,
        catalogRevision: String?,
        expectedSince: String?,
        evidenceDocument: [String: RuntimeJSONValue],
        decidedAt: String
    ) {
        self.commandId = commandId
        self.vrcode = vrcode
        self.expectedRevision = expectedRevision
        self.action = action
        self.supportState = supportState
        self.source = source
        self.recorderVersion = recorderVersion
        self.producerVersion = producerVersion
        self.protocolVersion = protocolVersion
        self.catalogRevision = catalogRevision
        self.expectedSince = expectedSince
        self.evidenceDocument = evidenceDocument
        self.decidedAt = decidedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandId = try container.decode(String.self, forKey: .commandId)
        vrcode = try container.decode(String.self, forKey: .vrcode)
        expectedRevision = try container.decode(Int.self, forKey: .expectedRevision)
        action = try container.decode(
            RuntimeRecorderObservabilityExpectationAction.self,
            forKey: .action
        )
        supportState = try container.decode(String?.self, forKey: .supportState)
        source = try container.decode(
            RuntimeRecorderObservabilityExpectationSource?.self,
            forKey: .source
        )
        recorderVersion = try container.decode(String?.self, forKey: .recorderVersion)
        producerVersion = try container.decode(String?.self, forKey: .producerVersion)
        protocolVersion = try container.decode(String?.self, forKey: .protocolVersion)
        catalogRevision = try container.decode(String?.self, forKey: .catalogRevision)
        expectedSince = try container.decode(String?.self, forKey: .expectedSince)
        evidenceDocument = try container.decode(
            [String: RuntimeJSONValue].self,
            forKey: .evidenceDocument
        )
        decidedAt = try container.decode(String.self, forKey: .decidedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandId, forKey: .commandId)
        try container.encode(vrcode, forKey: .vrcode)
        try container.encode(expectedRevision, forKey: .expectedRevision)
        try container.encode(action, forKey: .action)
        try container.encode(supportState, forKey: .supportState)
        try container.encode(source, forKey: .source)
        try container.encode(recorderVersion, forKey: .recorderVersion)
        try container.encode(producerVersion, forKey: .producerVersion)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(catalogRevision, forKey: .catalogRevision)
        try container.encode(expectedSince, forKey: .expectedSince)
        try container.encode(evidenceDocument, forKey: .evidenceDocument)
        try container.encode(decidedAt, forKey: .decidedAt)
    }
}

public enum RuntimeRecorderObservabilityExpectationReceiptState: String, Codable, Equatable, Sendable {
    case accepted
    case idempotent
    case revisionConflict
    case rejected
}

public struct RuntimeRecorderObservabilityExpectationReceipt: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderObservabilityExpectationReceiptState
    public let commandId: String
    public let eventId: String?
    public let vrcode: String
    public let currentRevision: Int
    public let failure: String?

    public init(
        state: RuntimeRecorderObservabilityExpectationReceiptState,
        commandId: String,
        eventId: String?,
        vrcode: String,
        currentRevision: Int,
        failure: String?
    ) {
        self.state = state
        self.commandId = commandId
        self.eventId = eventId
        self.vrcode = vrcode
        self.currentRevision = currentRevision
        self.failure = failure
    }
}

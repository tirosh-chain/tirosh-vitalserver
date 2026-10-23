import Foundation

public enum RuntimeRecorderObservabilityDetailState: String, Codable, Equatable, Sendable {
    case loaded
    case notReported
    case unavailable
}

public enum RuntimeRecorderObservabilityReadingState: String, Codable, Equatable, Sendable {
    case ok
    case missing
    case invalid
    case failed
    case unsupported
}

public enum RuntimeRecorderObservabilityProfileState: String, Codable, Equatable, Sendable {
    case associated
    case unassociated
    case missing
    case invalid
}

public enum RuntimeRecorderOperationalHealthState: String, Codable, Equatable, Sendable {
    case healthy
    case warning
    case critical
    case unknown
}

public enum RuntimeRecorderOperationalIssueSeverity: String, Codable, Equatable, Sendable {
    case warning
    case critical
}

public struct RuntimeRecorderOperationalIssue: Codable, Equatable, Sendable {
    public let code: String
    public let category: String
    public let severity: RuntimeRecorderOperationalIssueSeverity
    public let title: String
    public let detail: String
    public let field: String
}

public struct RuntimeRecorderOperationalHealth: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderOperationalHealthState
    @RuntimeRequiredNullable
    public private(set) var evaluatedAt: String?
    public let issueCount: Int
    public let issues: [RuntimeRecorderOperationalIssue]
}

public struct RuntimeRecorderObservabilityReading: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderObservabilityReadingState
    @RuntimeRequiredNullable
    public private(set) var value: RuntimeJSONValue?
    @RuntimeRequiredNullable
    public private(set) var detail: String?
    @RuntimeRequiredNullable
    public private(set) var observedAt: String?
}

public struct RuntimeRecorderObservabilitySupport: Codable, Equatable, Sendable {
    public let state: String
    @RuntimeRequiredNullable
    public private(set) var source: String?
    @RuntimeRequiredNullable
    public private(set) var expectedSince: String?
    @RuntimeRequiredNullable
    public private(set) var recorderVersion: String?
    @RuntimeRequiredNullable
    public private(set) var producerVersion: String?
    @RuntimeRequiredNullable
    public private(set) var protocolVersion: String?
}

public struct RuntimeRecorderObservabilityReport: Codable, Equatable, Sendable {
    public let state: String
    @RuntimeRequiredNullable
    public private(set) var receivedAt: String?
    @RuntimeRequiredNullable
    public private(set) var deviceObservedAt: String?
    @RuntimeRequiredNullable
    public private(set) var collectionState: String?
    public let readIssueCount: Int
}

public struct RuntimeRecorderObservabilityCollection: Codable, Equatable, Sendable {
    @RuntimeRequiredNullable
    public private(set) var powerIntervalSeconds: Int?
    @RuntimeRequiredNullable
    public private(set) var telemetryIntervalSeconds: Int?
    @RuntimeRequiredNullable
    public private(set) var observationIntervalSeconds: Int?
}

public struct RuntimeRecorderObservabilityCapability: Codable, Equatable, Sendable {
    public let state: String
    @RuntimeRequiredNullable
    public private(set) var source: String?
    @RuntimeRequiredNullable
    public private(set) var detail: String?
}

public struct RuntimeRecorderObservabilityProfile: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderObservabilityProfileState
    @RuntimeRequiredNullable
    public private(set) var receivedAt: String?
    @RuntimeRequiredNullable
    public private(set) var deviceObservedAt: String?
    @RuntimeRequiredNullable
    public private(set) var deviceId: String?
    @RuntimeRequiredNullable
    public private(set) var bootId: String?
    public let software: [String: RuntimeRecorderObservabilityReading]
    @RuntimeRequiredNullable
    public private(set) var collection: RuntimeRecorderObservabilityCollection?
    public let capabilities: [String: RuntimeRecorderObservabilityCapability]
}

public struct RuntimeRecorderObservabilityBoot: Codable, Equatable, Sendable {
    public let state: String
    public let orderingState: String
    @RuntimeRequiredNullable
    public private(set) var bootId: String?
    @RuntimeRequiredNullable
    public private(set) var startedAt: String?
    @RuntimeRequiredNullable
    public private(set) var cleanShutdownAt: String?
}

/// Health of the evidence collectors on the Recorder. This is reported by the
/// Recorder; it is deliberately not inferred from the absence of incidents.
public struct RuntimeRecorderObservabilityEvidenceHealth: Codable, Equatable, Sendable {
    public let state: String
    @RuntimeRequiredNullable
    public private(set) var checkedAt: String?
    public let checkCount: Int
    @RuntimeRequiredNullable
    public private(set) var detail: String?
}

/// Current, policy-produced incident assessment for the latest observation.
/// Historical incidents are represented separately by the incident history API.
public struct RuntimeRecorderObservabilityIncidentState: Codable, Equatable, Sendable {
    public let state: String
    @RuntimeRequiredNullable
    public private(set) var policyVersion: String?
    @RuntimeRequiredNullable
    public private(set) var bootLoopState: String?
    @RuntimeRequiredNullable
    public private(set) var repeatedUndervoltageState: String?
    @RuntimeRequiredNullable
    public private(set) var evidenceState: String?
    @RuntimeRequiredNullable
    public private(set) var consecutiveUnexpectedBoots: Int?
    @RuntimeRequiredNullable
    public private(set) var undervoltageBootsConsidered: Int?
}

public struct RuntimeRecorderObservabilityNetworkInterface: Codable, Equatable, Sendable {
    public let name: String
    public let operState: RuntimeRecorderObservabilityReading
    public let carrier: RuntimeRecorderObservabilityReading
    public let rxErrors: RuntimeRecorderObservabilityReading
    public let txErrors: RuntimeRecorderObservabilityReading
}

public struct RuntimeRecorderObservabilityReadings: Codable, Equatable, Sendable {
    public let temperatureCelsius: RuntimeRecorderObservabilityReading
    public let memoryAvailableBytes: RuntimeRecorderObservabilityReading
    public let memoryTotalBytes: RuntimeRecorderObservabilityReading
    public let rootUsedPercent: RuntimeRecorderObservabilityReading
    public let dataUsedPercent: RuntimeRecorderObservabilityReading
    public let recorderActiveState: RuntimeRecorderObservabilityReading
    public let publisherActiveState: RuntimeRecorderObservabilityReading
    public let publisherBufferBytes: RuntimeRecorderObservabilityReading
    public let publisherBufferLimitBytes: RuntimeRecorderObservabilityReading
    public let networkInterfaces: [RuntimeRecorderObservabilityNetworkInterface]
}

public struct RuntimeRecorderObservabilityReadIssue: Codable, Equatable, Sendable {
    public let field: String
    public let state: String
    public let detail: String
}

public struct RuntimeRecorderObservabilityDetail: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderObservabilityDetailState
    public let vrcode: String
    public let support: RuntimeRecorderObservabilitySupport
    public let report: RuntimeRecorderObservabilityReport
    public let profile: RuntimeRecorderObservabilityProfile
    public let boot: RuntimeRecorderObservabilityBoot
    public let evidenceHealth: RuntimeRecorderObservabilityEvidenceHealth
    public let incidentState: RuntimeRecorderObservabilityIncidentState
    public let operationalHealth: RuntimeRecorderOperationalHealth
    public let readings: RuntimeRecorderObservabilityReadings
    public let readIssues: [RuntimeRecorderObservabilityReadIssue]
    @RuntimeRequiredNullable
    public private(set) var readError: String?

    public static func unavailable(
        vrcode: String,
        readError: String
    ) -> RuntimeRecorderObservabilityDetail {
        let missing = RuntimeRecorderObservabilityReading(
            state: .missing,
            value: nil,
            detail: "health observation is unavailable",
            observedAt: nil
        )
        return RuntimeRecorderObservabilityDetail(
            state: .unavailable,
            vrcode: vrcode,
            support: RuntimeRecorderObservabilitySupport(
                state: "unknown",
                source: nil,
                expectedSince: nil,
                recorderVersion: nil,
                producerVersion: nil,
                protocolVersion: nil
            ),
            report: RuntimeRecorderObservabilityReport(
                state: "readFailed",
                receivedAt: nil,
                deviceObservedAt: nil,
                collectionState: nil,
                readIssueCount: 0
            ),
            profile: RuntimeRecorderObservabilityProfile(
                state: .missing,
                receivedAt: nil,
                deviceObservedAt: nil,
                deviceId: nil,
                bootId: nil,
                software: [:],
                collection: nil,
                capabilities: [:]
            ),
            boot: RuntimeRecorderObservabilityBoot(
                state: "notReported",
                orderingState: "unknown",
                bootId: nil,
                startedAt: nil,
                cleanShutdownAt: nil
            ),
            evidenceHealth: RuntimeRecorderObservabilityEvidenceHealth(
                state: "notReported",
                checkedAt: nil,
                checkCount: 0,
                detail: nil
            ),
            incidentState: RuntimeRecorderObservabilityIncidentState(
                state: "notReported",
                policyVersion: nil,
                bootLoopState: nil,
                repeatedUndervoltageState: nil,
                evidenceState: nil,
                consecutiveUnexpectedBoots: nil,
                undervoltageBootsConsidered: nil
            ),
            operationalHealth: RuntimeRecorderOperationalHealth(
                state: .unknown,
                evaluatedAt: nil,
                issueCount: 0,
                issues: []
            ),
            readings: RuntimeRecorderObservabilityReadings(
                temperatureCelsius: missing,
                memoryAvailableBytes: missing,
                memoryTotalBytes: missing,
                rootUsedPercent: missing,
                dataUsedPercent: missing,
                recorderActiveState: missing,
                publisherActiveState: missing,
                publisherBufferBytes: missing,
                publisherBufferLimitBytes: missing,
                networkInterfaces: []
            ),
            readIssues: [],
            readError: readError
        )
    }
}

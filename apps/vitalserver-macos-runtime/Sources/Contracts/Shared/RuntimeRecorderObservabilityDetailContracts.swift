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

public struct RuntimeRecorderObservabilityReading: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderObservabilityReadingState
    public let value: RuntimeJSONValue?
    public let detail: String?
    public let observedAt: String?
}

public struct RuntimeRecorderObservabilitySupport: Codable, Equatable, Sendable {
    public let state: String
    public let source: String?
    public let expectedSince: String?
    public let recorderVersion: String?
    public let producerVersion: String?
    public let protocolVersion: String?
}

public struct RuntimeRecorderObservabilityReport: Codable, Equatable, Sendable {
    public let state: String
    public let receivedAt: String?
    public let deviceObservedAt: String?
    public let collectionState: String?
    public let readIssueCount: Int
}

public struct RuntimeRecorderObservabilityCollection: Codable, Equatable, Sendable {
    public let powerIntervalSeconds: Int?
    public let telemetryIntervalSeconds: Int?
    public let observationIntervalSeconds: Int?
}

public struct RuntimeRecorderObservabilityCapability: Codable, Equatable, Sendable {
    public let state: String
    public let source: String?
    public let detail: String?
}

public struct RuntimeRecorderObservabilityProfile: Codable, Equatable, Sendable {
    public let state: RuntimeRecorderObservabilityProfileState
    public let receivedAt: String?
    public let deviceObservedAt: String?
    public let deviceId: String?
    public let bootId: String?
    public let software: [String: RuntimeRecorderObservabilityReading]
    public let collection: RuntimeRecorderObservabilityCollection?
    public let capabilities: [String: RuntimeRecorderObservabilityCapability]
}

public struct RuntimeRecorderObservabilityBoot: Codable, Equatable, Sendable {
    public let state: String
    public let bootId: String?
    public let startedAt: String?
    public let cleanShutdownAt: String?
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
    public let readings: RuntimeRecorderObservabilityReadings
    public let readIssues: [RuntimeRecorderObservabilityReadIssue]
    public let readError: String?

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
                bootId: nil,
                startedAt: nil,
                cleanShutdownAt: nil
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

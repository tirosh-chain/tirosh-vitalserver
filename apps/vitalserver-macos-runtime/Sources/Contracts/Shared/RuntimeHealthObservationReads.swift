import Foundation

public struct RuntimeContainerLogsMetadata {
    public let present: Bool
    public let bytes: UInt64?
    public let updatedAt: String?
    public let error: String?

    public init(present: Bool, bytes: UInt64?, updatedAt: String?, error: String?) {
        self.present = present
        self.bytes = bytes
        self.updatedAt = updatedAt
        self.error = error
    }
}

public enum RuntimeGuestControlReadinessRead: Equatable, Sendable {
    case notReported
    case loaded(vmIP: String?, readiness: RuntimeGuestControlReadiness)
    case failed(vmIP: String?, message: String)
}

public enum RuntimeRecorderIngressStatusReadState: String, Codable, Equatable, Sendable {
    case notRead
    case loaded
    case commandFailed
    case emptyResponse
    case outputInvalid
    case invalidResponse
    case readFailed
}

public struct RuntimeRecorderIngressStatusReadResult: Codable, Equatable, Sendable {
    public let readState: RuntimeRecorderIngressStatusReadState
    public let httpStatus: String
    public let document: RuntimeRecorderIngressStatusDocument?
    public let readError: String?

    public init(
        readState: RuntimeRecorderIngressStatusReadState? = nil,
        httpStatus: String,
        document: RuntimeRecorderIngressStatusDocument?,
        readError: String?
    ) {
        self.readState = readState ?? RuntimeRecorderIngressStatusReadResult.readState(
            httpStatus: httpStatus,
            document: document,
            readError: readError
        )
        self.httpStatus = httpStatus
        self.document = document
        self.readError = readError
    }

    private static func readState(
        httpStatus: String,
        document: RuntimeRecorderIngressStatusDocument?,
        readError: String?
    ) -> RuntimeRecorderIngressStatusReadState {
        if document != nil, readError == nil {
            return .loaded
        }
        guard let readError, !readError.isEmpty else {
            return .notRead
        }
        if readError.hasPrefix("command-failed") {
            return .commandFailed
        }
        if readError.hasPrefix("empty-response") {
            return .emptyResponse
        }
        if readError.hasPrefix("output-invalid") {
            return .outputInvalid
        }
        if httpStatus == RuntimeHTTPStatusText.invalidResponse || readError.hasPrefix("decode-failed") {
            return .invalidResponse
        }
        return .readFailed
    }

    private enum CodingKeys: String, CodingKey {
        case readState
        case httpStatus
        case document
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let readState = try container.decode(RuntimeRecorderIngressStatusReadState.self, forKey: .readState)
        let httpStatus = try container.decode(String.self, forKey: .httpStatus)
        let document = try container.decodeRequiredNullable(
            RuntimeRecorderIngressStatusDocument.self,
            forKey: .document
        )
        let readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
        try Self.validateDecoded(readState: readState, document: document, readError: readError)
        self.readState = readState
        self.httpStatus = httpStatus
        self.document = document
        self.readError = readError
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readState, forKey: .readState)
        try container.encode(httpStatus, forKey: .httpStatus)
        if let document {
            try container.encode(document, forKey: .document)
        } else {
            try container.encodeNil(forKey: .document)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    private static func validateDecoded(
        readState: RuntimeRecorderIngressStatusReadState,
        document: RuntimeRecorderIngressStatusDocument?,
        readError: String?
    ) throws {
        switch readState {
        case .loaded:
            if document == nil {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.document],
                        debugDescription: "loaded recorder ingress status reads must include document"
                    )
                )
            }
            if !readError.isBlankOrMissing {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.readError],
                        debugDescription: "loaded recorder ingress status reads must not include readError"
                    )
                )
            }
        case .commandFailed, .emptyResponse, .outputInvalid, .invalidResponse, .readFailed:
            if readError.isBlankOrMissing {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.readError],
                        debugDescription: "\(readState.rawValue) recorder ingress status reads must include readError"
                    )
                )
            }
        case .notRead:
            break
        }
    }
}

public enum RuntimeRedisRelayStatusReadState: String, Codable, Equatable, Sendable {
    case notRead
    case loaded
    case invalidResponse
    case readFailed
}

public struct RuntimeRedisRelayStatusReadResult: Codable, Equatable, Sendable {
    public let readState: RuntimeRedisRelayStatusReadState
    public let document: RuntimeRedisRelayStatus?
    public let readError: String?

    public init(
        readState: RuntimeRedisRelayStatusReadState? = nil,
        document: RuntimeRedisRelayStatus?,
        readError: String?
    ) {
        self.readState = readState ?? RuntimeRedisRelayStatusReadResult.readState(
            document: document,
            readError: readError
        )
        self.document = document
        self.readError = readError
    }

    private static func readState(
        document: RuntimeRedisRelayStatus?,
        readError: String?
    ) -> RuntimeRedisRelayStatusReadState {
        if document != nil, readError == nil {
            return .loaded
        }
        guard let readError, !readError.isEmpty else {
            return .notRead
        }
        if readError.hasPrefix("decode-failed") {
            return .invalidResponse
        }
        return .readFailed
    }

    private enum CodingKeys: String, CodingKey {
        case readState
        case document
        case readError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let readState = try container.decode(RuntimeRedisRelayStatusReadState.self, forKey: .readState)
        let document = try container.decodeRequiredNullable(RuntimeRedisRelayStatus.self, forKey: .document)
        let readError = try container.decodeRequiredNullable(String.self, forKey: .readError)
        try Self.validateDecoded(readState: readState, document: document, readError: readError)
        self.readState = readState
        self.document = document
        self.readError = readError
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readState, forKey: .readState)
        if let document {
            try container.encode(document, forKey: .document)
        } else {
            try container.encodeNil(forKey: .document)
        }
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }

    private static func validateDecoded(
        readState: RuntimeRedisRelayStatusReadState,
        document: RuntimeRedisRelayStatus?,
        readError: String?
    ) throws {
        switch readState {
        case .loaded:
            if document == nil {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.document],
                        debugDescription: "loaded Redis Relay status reads must include document"
                    )
                )
            }
            if !readError.isBlankOrMissing {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.readError],
                        debugDescription: "loaded Redis Relay status reads must not include readError"
                    )
                )
            }
        case .invalidResponse, .readFailed:
            if readError.isBlankOrMissing {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [CodingKeys.readError],
                        debugDescription: "\(readState.rawValue) Redis Relay status reads must include readError"
                    )
                )
            }
        case .notRead:
            break
        }
    }
}

public struct RuntimeHostProxyListenerObservation {
    public let port: Int
    public let scanResult: RuntimeHostProxyListenerScanResult
    public let expectedNginxPID: RuntimeProxyNginxPIDReadResult

    public init(
        port: Int,
        scanResult: RuntimeHostProxyListenerScanResult,
        expectedNginxPID: RuntimeProxyNginxPIDReadResult
    ) {
        self.port = port
        self.scanResult = scanResult
        self.expectedNginxPID = expectedNginxPID
    }
}

public struct RuntimeHealthObservationReads {
    public let vmExecutable: RuntimeFileState
    public let proxyExecutable: RuntimeFileState
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmLifecycleLoadResult: RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument>
    public let guestAddressRead: RuntimeGuestAddressReadResult
    public let guestControlReadiness: RuntimeGuestControlReadinessRead
    public let proxyPortReadState: RuntimeProxyPortReadState
    public let hostProxyHTTP: RuntimeHTTPProbeResult?
    public let redisUIHTTP: RuntimeHTTPProbeResult?
    public let swaggerUIHTTP: RuntimeHTTPProbeResult?
    public let recorderIngressStatus: RuntimeRecorderIngressStatusReadResult?
    public let vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument>
    public let containerLogsMetadata: RuntimeContainerLogsMetadata
    public let proxyListenerObservation: RuntimeHostProxyListenerObservation?
    public let observedAt: Date

    public init(
        vmExecutable: RuntimeFileState,
        proxyExecutable: RuntimeFileState,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmLifecycleLoadResult: RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument>,
        guestAddressRead: RuntimeGuestAddressReadResult = .notReported,
        guestControlReadiness: RuntimeGuestControlReadinessRead = .notReported,
        proxyPortReadState: RuntimeProxyPortReadState,
        hostProxyHTTP: RuntimeHTTPProbeResult?,
        redisUIHTTP: RuntimeHTTPProbeResult?,
        swaggerUIHTTP: RuntimeHTTPProbeResult?,
        recorderIngressStatus: RuntimeRecorderIngressStatusReadResult?,
        vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument> = .notReported,
        containerLogsMetadata: RuntimeContainerLogsMetadata,
        proxyListenerObservation: RuntimeHostProxyListenerObservation?,
        observedAt: Date
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmLifecycleLoadResult = vmLifecycleLoadResult
        self.guestAddressRead = guestAddressRead
        self.guestControlReadiness = guestControlReadiness
        self.proxyPortReadState = proxyPortReadState
        self.hostProxyHTTP = hostProxyHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.recorderIngressStatus = recorderIngressStatus
        self.vitalDBObservation = vitalDBObservation
        self.containerLogsMetadata = containerLogsMetadata
        self.proxyListenerObservation = proxyListenerObservation
        self.observedAt = observedAt
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredNullable<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "Missing required nullable field '\(key.stringValue)'"
                )
            )
        }
        return try decodeIfPresent(type, forKey: key)
    }
}

private extension Optional where Wrapped == String {
    var isBlankOrMissing: Bool {
        switch self {
        case .none:
            return true
        case let .some(value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

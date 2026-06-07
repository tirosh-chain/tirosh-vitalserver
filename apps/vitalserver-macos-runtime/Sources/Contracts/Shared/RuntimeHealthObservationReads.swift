import Foundation

public struct RuntimeGuestRuntimeStateObservation {
    public let loadedState: GuestRuntimeStateDocument?
    public let freshState: GuestRuntimeStateDocument?
    public let isFresh: Bool
    public let readIssue: RuntimeGuestRuntimeStateReadIssue?

    public var isPresent: Bool {
        loadedState != nil
    }

    public init(
        loadedState: GuestRuntimeStateDocument?,
        freshState: GuestRuntimeStateDocument?,
        isFresh: Bool,
        readIssue: RuntimeGuestRuntimeStateReadIssue? = nil
    ) {
        self.loadedState = loadedState
        self.freshState = freshState
        self.isFresh = isFresh
        self.readIssue = readIssue
    }
}

public enum RuntimeGuestRuntimeStateReadIssue: Equatable, Sendable {
    case loadFailed(String)
    case metadataReadFailed(String)
}

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

public enum RuntimeFileMetadataReadState: String, Codable, Equatable, Sendable {
    case notRead
    case loaded
    case readFailed
}

public struct RuntimeFileModifiedAtReadResult {
    public let readState: RuntimeFileMetadataReadState
    public let updatedAt: String?
    public let readError: String?

    public init(
        readState: RuntimeFileMetadataReadState? = nil,
        updatedAt: String?,
        readError: String?
    ) {
        self.readState = readState ?? RuntimeFileModifiedAtReadResult.readState(
            updatedAt: updatedAt,
            readError: readError
        )
        self.updatedAt = updatedAt
        self.readError = readError
    }

    public static func notRead() -> RuntimeFileModifiedAtReadResult {
        RuntimeFileModifiedAtReadResult(readState: .notRead, updatedAt: nil, readError: nil)
    }

    private static func readState(
        updatedAt: String?,
        readError: String?
    ) -> RuntimeFileMetadataReadState {
        if readError != nil {
            return .readFailed
        }
        if updatedAt != nil {
            return .loaded
        }
        return .notRead
    }
}

public enum RuntimeAuditProxyStatusReadState: String, Codable, Equatable, Sendable {
    case notRead
    case loaded
    case skippedMissingProxyPort
    case commandFailed
    case emptyResponse
    case outputInvalid
    case invalidResponse
    case readFailed
}

public struct RuntimeAuditProxyStatusReadResult {
    public let readState: RuntimeAuditProxyStatusReadState
    public let httpStatus: String
    public let document: RuntimeAuditProxyStatusDocument?
    public let readError: String?

    public init(
        readState: RuntimeAuditProxyStatusReadState? = nil,
        httpStatus: String,
        document: RuntimeAuditProxyStatusDocument?,
        readError: String?
    ) {
        self.readState = readState ?? RuntimeAuditProxyStatusReadResult.readState(
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
        document: RuntimeAuditProxyStatusDocument?,
        readError: String?
    ) -> RuntimeAuditProxyStatusReadState {
        if document != nil, readError == nil {
            return .loaded
        }
        guard let readError, !readError.isEmpty else {
            return .notRead
        }
        if readError == RuntimeHTTPStatusText.missingProxyPort {
            return .skippedMissingProxyPort
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
    public let guestRuntimeState: RuntimeGuestRuntimeStateObservation
    public let proxyPortReadState: RuntimeProxyPortReadState
    public let hostProxyHTTP: RuntimeHTTPProbeResult?
    public let redisUIHTTP: RuntimeHTTPProbeResult?
    public let swaggerUIHTTP: RuntimeHTTPProbeResult?
    public let auditProxyStatus: RuntimeAuditProxyStatusReadResult?
    public let runtimeStateFileModifiedAt: RuntimeFileModifiedAtReadResult
    public let containerLogsMetadata: RuntimeContainerLogsMetadata
    public let proxyListenerObservation: RuntimeHostProxyListenerObservation?
    public let guestBootstrapResult: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>
    public let observedAt: Date
    public let guestBootstrapFreshnessGraceSeconds: TimeInterval

    public init(
        vmExecutable: RuntimeFileState,
        proxyExecutable: RuntimeFileState,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmLifecycleLoadResult: RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument>,
        guestRuntimeState: RuntimeGuestRuntimeStateObservation,
        proxyPortReadState: RuntimeProxyPortReadState,
        hostProxyHTTP: RuntimeHTTPProbeResult?,
        redisUIHTTP: RuntimeHTTPProbeResult?,
        swaggerUIHTTP: RuntimeHTTPProbeResult?,
        auditProxyStatus: RuntimeAuditProxyStatusReadResult?,
        runtimeStateFileModifiedAt: RuntimeFileModifiedAtReadResult,
        containerLogsMetadata: RuntimeContainerLogsMetadata,
        proxyListenerObservation: RuntimeHostProxyListenerObservation?,
        guestBootstrapResult: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>,
        observedAt: Date,
        guestBootstrapFreshnessGraceSeconds: TimeInterval
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmLifecycleLoadResult = vmLifecycleLoadResult
        self.guestRuntimeState = guestRuntimeState
        self.proxyPortReadState = proxyPortReadState
        self.hostProxyHTTP = hostProxyHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.auditProxyStatus = auditProxyStatus
        self.runtimeStateFileModifiedAt = runtimeStateFileModifiedAt
        self.containerLogsMetadata = containerLogsMetadata
        self.proxyListenerObservation = proxyListenerObservation
        self.guestBootstrapResult = guestBootstrapResult
        self.observedAt = observedAt
        self.guestBootstrapFreshnessGraceSeconds = guestBootstrapFreshnessGraceSeconds
    }
}

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
    public let guestControlReadiness: RuntimeGuestControlReadinessRead
    public let proxyPortReadState: RuntimeProxyPortReadState
    public let hostProxyHTTP: RuntimeHTTPProbeResult?
    public let redisUIHTTP: RuntimeHTTPProbeResult?
    public let swaggerUIHTTP: RuntimeHTTPProbeResult?
    public let recorderIngressStatus: RuntimeRecorderIngressStatusReadResult?
    public let vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument>
    public let containerLogsMetadata: RuntimeContainerLogsMetadata
    public let proxyListenerObservation: RuntimeHostProxyListenerObservation?
    public let guestBootstrapResult: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>
    public let guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]>
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
        guestControlReadiness: RuntimeGuestControlReadinessRead = .notReported,
        proxyPortReadState: RuntimeProxyPortReadState,
        hostProxyHTTP: RuntimeHTTPProbeResult?,
        redisUIHTTP: RuntimeHTTPProbeResult?,
        swaggerUIHTTP: RuntimeHTTPProbeResult?,
        recorderIngressStatus: RuntimeRecorderIngressStatusReadResult?,
        vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument> = .notReported,
        containerLogsMetadata: RuntimeContainerLogsMetadata,
        proxyListenerObservation: RuntimeHostProxyListenerObservation?,
        guestBootstrapResult: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>,
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported,
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
        self.guestControlReadiness = guestControlReadiness
        self.proxyPortReadState = proxyPortReadState
        self.hostProxyHTTP = hostProxyHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.recorderIngressStatus = recorderIngressStatus
        self.vitalDBObservation = vitalDBObservation
        self.containerLogsMetadata = containerLogsMetadata
        self.proxyListenerObservation = proxyListenerObservation
        self.guestBootstrapResult = guestBootstrapResult
        self.guestServiceStatuses = guestServiceStatuses
        self.observedAt = observedAt
        self.guestBootstrapFreshnessGraceSeconds = guestBootstrapFreshnessGraceSeconds
    }
}

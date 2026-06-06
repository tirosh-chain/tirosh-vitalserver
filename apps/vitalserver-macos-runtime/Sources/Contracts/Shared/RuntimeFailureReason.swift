import Foundation

public enum RuntimeDomainErrorCategory: String, Codable, Equatable, Sendable {
    case installation
    case vmLifecycle
    case hostProxy
    case hostService
    case guestNetworking
    case guestAgent
    case guestBootstrap
    case guestStorage
    case container
    case vitalDB
    case auxiliaryUI
    case hostResources
    case configuration
    case observability
    case unknown
}

public enum RuntimeDomainErrorSeverity: String, Codable, Equatable, Sendable {
    case warning
    case critical
}

public enum RuntimeDomainRecoveryAction: String, Codable, Equatable, Sendable {
    case installRuntime
    case restartVMService
    case restartProxyService
    case restartWatchdogService
    case waitForGuest
    case restartGuestAgent
    case repairGuestBootstrap
    case restartContainerServices
    case repairProxyConfiguration
    case freeProxyPort
    case inspectVitalDBObservation
    case backupAndRecreateVM
    case fixConfiguration
    case freeHostResources
    case inspectLogs
}

public struct RuntimeDomainError: Codable, Equatable, Sendable {
    public let code: RuntimeFailureReason
    public let category: RuntimeDomainErrorCategory
    public let severity: RuntimeDomainErrorSeverity
    public let recoveryAction: RuntimeDomainRecoveryAction

    public init(_ code: RuntimeFailureReason) {
        self.code = code
        self.category = code.domainCategory
        self.severity = code.domainSeverity
        self.recoveryAction = code.recoveryAction
    }
}

public enum RuntimeFailureReason: Codable, Equatable, Sendable {
    case missingVMBin
    case missingProxyRunner
    case missingRootfsBase
    case missingVMDisk
    case vmService(String)
    case guestLogSyncService(String)
    case proxyService(String)
    case watchdogService(String)
    case hostProxyHTTP(String)
    case redisUIHTTP(String)
    case swaggerUIHTTP(String)
    case guestHTTP(String)
    case guestHTTPProbeFailed(String)
    case guestRuntimeStateStale
    case auditProxyHTTP(String)
    case containerService(service: String, state: String)
    case containerObservationMissing
    case containerObservationReadFailed(String)
    case vitalDBAnomaly(kind: String, subject: String)
    case vitalDBObservationMissing
    case vitalDBObservationReadFailed(String)
    case proxyPortInUse(port: Int, listeners: String)
    case guestBootstrapResultMissing
    case guestBootstrapResultUnavailable
    case guestBootstrapMissingRuntimePackages
    case guestBootstrapFailed
    case runtimeStatusDocumentMissing
    case runtimeStatusDocumentStale
    case runtimeStatusDocumentInvalid
    case guestRuntimeStateInvalid
    case observabilityEventStoreUnavailable
    case observabilityEventStoreCorrupt
    case vmLifecycleDocumentInvalid
    case vmLifecycleDocumentStale
    case vmPidFileStale
    case vmProcessExited
    case launchdServiceCrashed(service: String, exitCode: Int)
    case launchdServiceThrottled(service: String)
    case hostProxyListenerMismatch(port: Int, listeners: String)
    case hostProxyListenerScanUnavailable
    case hostProxyListenerScanFailed(port: Int, exitCode: Int)
    case hostProxyConfigInvalid
    case httpProbeTimedOut(target: String)
    case httpProbeConnectionRefused(target: String)
    case containerExited(service: String, exitCode: Int)
    case containerRestartLoop(service: String)
    case vitalDBObservationStale
    case unknown(String)

    public init(vmError: RuntimeVMError) {
        switch vmError {
        case .missingExecutable:
            self = .missingVMBin
        case .missingRootfsBase:
            self = .missingRootfsBase
        case .missingDisk:
            self = .missingVMDisk
        case .serviceNotLoaded(let state):
            self = .vmService(state)
        case .missingIPAddress:
            self = .guestHTTP(RuntimeHTTPStatusText.missingVMIP)
        case .runtimeStateMissing:
            self = .unknown(vmError.rawValue)
        case .runtimeStateInvalid:
            self = .guestRuntimeStateInvalid
        case .runtimeStateStale:
            self = .guestRuntimeStateStale
        case .launchFailed, .invalidConfiguration, .hostResourceUnavailable,
             .diskAttachmentInvalid, .guestFilesystemError, .guestFilesystemReadOnly, .guestDiskIO:
            self = .unknown(vmError.rawValue)
        case .guestHTTP(let status):
            self = .guestHTTP(status)
        case .guestHTTPProbeFailed(let status):
            self = .guestHTTPProbeFailed(status)
        case .guestBootstrapResultMissing:
            self = .guestBootstrapResultMissing
        case .guestBootstrapResultUnavailable:
            self = .guestBootstrapResultUnavailable
        case .guestBootstrapMissingRuntimePackages:
            self = .guestBootstrapMissingRuntimePackages
        case .guestBootstrapFailed:
            self = .guestBootstrapFailed
        case .unknown(let value):
            self = .unknown(value)
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "missing-vm-bin":
            self = .missingVMBin
        case "missing-proxy-runner":
            self = .missingProxyRunner
        case "missing-rootfs-base":
            self = .missingRootfsBase
        case "missing-vm-disk":
            self = .missingVMDisk
        case "guest-bootstrap-missing-runtime-packages":
            self = .guestBootstrapMissingRuntimePackages
        case "guest-bootstrap-result-missing":
            self = .guestBootstrapResultMissing
        case "guest-bootstrap-result-unavailable":
            self = .guestBootstrapResultUnavailable
        case "guest-bootstrap-failed":
            self = .guestBootstrapFailed
        case "guest-runtime-state-stale":
            self = .guestRuntimeStateStale
        case "runtime-status-document-missing":
            self = .runtimeStatusDocumentMissing
        case "runtime-status-document-stale":
            self = .runtimeStatusDocumentStale
        case "runtime-status-document-invalid":
            self = .runtimeStatusDocumentInvalid
        case "guest-runtime-state-invalid":
            self = .guestRuntimeStateInvalid
        case "observability-event-store-unavailable":
            self = .observabilityEventStoreUnavailable
        case "observability-event-store-corrupt":
            self = .observabilityEventStoreCorrupt
        case "container-observation-missing":
            self = .containerObservationMissing
        case "vitaldb-observation-missing":
            self = .vitalDBObservationMissing
        case "vm-lifecycle-document-invalid":
            self = .vmLifecycleDocumentInvalid
        case "vm-lifecycle-document-stale":
            self = .vmLifecycleDocumentStale
        case "vm-pid-file-stale":
            self = .vmPidFileStale
        case "vm-process-exited":
            self = .vmProcessExited
        case "host-proxy-config-invalid":
            self = .hostProxyConfigInvalid
        case "host-proxy-listener-scan-unavailable":
            self = .hostProxyListenerScanUnavailable
        case "vitaldb-observation-stale":
            self = .vitalDBObservationStale
        default:
            if rawValue.hasPrefix("vm-service-") {
                self = .vmService(String(rawValue.dropFirst("vm-service-".count)))
            } else if rawValue.hasPrefix("guest-log-sync-service-") {
                self = .guestLogSyncService(String(rawValue.dropFirst("guest-log-sync-service-".count)))
            } else if rawValue.hasPrefix("proxy-service-") {
                self = .proxyService(String(rawValue.dropFirst("proxy-service-".count)))
            } else if rawValue.hasPrefix("watchdog-service-") {
                self = .watchdogService(String(rawValue.dropFirst("watchdog-service-".count)))
            } else if rawValue.hasPrefix("host-proxy-http-") {
                self = .hostProxyHTTP(String(rawValue.dropFirst("host-proxy-http-".count)))
            } else if rawValue.hasPrefix("redis-ui-http-") {
                self = .redisUIHTTP(String(rawValue.dropFirst("redis-ui-http-".count)))
            } else if rawValue.hasPrefix("swagger-ui-http-") {
                self = .swaggerUIHTTP(String(rawValue.dropFirst("swagger-ui-http-".count)))
            } else if rawValue.hasPrefix("guest-http-probe-failed-") {
                self = .guestHTTPProbeFailed(String(rawValue.dropFirst("guest-http-probe-failed-".count)))
            } else if rawValue.hasPrefix("guest-http-") {
                self = .guestHTTP(String(rawValue.dropFirst("guest-http-".count)))
            } else if rawValue.hasPrefix("audit-proxy-http-") {
                self = .auditProxyHTTP(String(rawValue.dropFirst("audit-proxy-http-".count)))
            } else if rawValue.hasPrefix("container-observation-read-failed-") {
                self = .containerObservationReadFailed(
                    String(rawValue.dropFirst("container-observation-read-failed-".count))
                )
            } else if rawValue.hasPrefix("vitaldb-observation-read-failed-") {
                self = .vitalDBObservationReadFailed(
                    String(rawValue.dropFirst("vitaldb-observation-read-failed-".count))
                )
            } else if let parsed = RuntimeFailureReason.parseContainerService(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseVitalDBAnomaly(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseProxyPortInUse(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseLaunchdServiceCrashed(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseLaunchdServiceThrottled(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseHostProxyListenerMismatch(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseHostProxyListenerScanFailed(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseHTTPProbeTimedOut(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseHTTPProbeConnectionRefused(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseContainerExited(rawValue) {
                self = parsed
            } else if let parsed = RuntimeFailureReason.parseContainerRestartLoop(rawValue) {
                self = parsed
            } else {
                self = .unknown(rawValue)
            }
        }
    }

    public var rawValue: String {
        switch self {
        case .missingVMBin:
            return "missing-vm-bin"
        case .missingProxyRunner:
            return "missing-proxy-runner"
        case .missingRootfsBase:
            return "missing-rootfs-base"
        case .missingVMDisk:
            return "missing-vm-disk"
        case .vmService(let state):
            return "vm-service-\(state)"
        case .guestLogSyncService(let state):
            return "guest-log-sync-service-\(state)"
        case .proxyService(let state):
            return "proxy-service-\(state)"
        case .watchdogService(let state):
            return "watchdog-service-\(state)"
        case .hostProxyHTTP(let status):
            return "host-proxy-http-\(status)"
        case .redisUIHTTP(let status):
            return "redis-ui-http-\(status)"
        case .swaggerUIHTTP(let status):
            return "swagger-ui-http-\(status)"
        case .guestHTTP(let status):
            return "guest-http-\(status)"
        case .guestHTTPProbeFailed(let status):
            return "guest-http-probe-failed-\(status)"
        case .guestRuntimeStateStale:
            return "guest-runtime-state-stale"
        case .auditProxyHTTP(let status):
            return "audit-proxy-http-\(status)"
        case .containerService(let service, let state):
            return "container-service-\(service)-state-\(state)"
        case .containerObservationMissing:
            return "container-observation-missing"
        case .containerObservationReadFailed(let message):
            return "container-observation-read-failed-\(message)"
        case .vitalDBAnomaly(let kind, let subject):
            return "vitaldb-anomaly-\(kind)-subject-\(subject)"
        case .vitalDBObservationMissing:
            return "vitaldb-observation-missing"
        case .vitalDBObservationReadFailed(let message):
            return "vitaldb-observation-read-failed-\(message)"
        case .proxyPortInUse(let port, let listeners):
            return "proxy-port-\(port)-in-use-by-\(listeners)"
        case .guestBootstrapResultMissing:
            return "guest-bootstrap-result-missing"
        case .guestBootstrapResultUnavailable:
            return "guest-bootstrap-result-unavailable"
        case .guestBootstrapMissingRuntimePackages:
            return "guest-bootstrap-missing-runtime-packages"
        case .guestBootstrapFailed:
            return "guest-bootstrap-failed"
        case .runtimeStatusDocumentMissing:
            return "runtime-status-document-missing"
        case .runtimeStatusDocumentStale:
            return "runtime-status-document-stale"
        case .runtimeStatusDocumentInvalid:
            return "runtime-status-document-invalid"
        case .guestRuntimeStateInvalid:
            return "guest-runtime-state-invalid"
        case .observabilityEventStoreUnavailable:
            return "observability-event-store-unavailable"
        case .observabilityEventStoreCorrupt:
            return "observability-event-store-corrupt"
        case .vmLifecycleDocumentInvalid:
            return "vm-lifecycle-document-invalid"
        case .vmLifecycleDocumentStale:
            return "vm-lifecycle-document-stale"
        case .vmPidFileStale:
            return "vm-pid-file-stale"
        case .vmProcessExited:
            return "vm-process-exited"
        case .launchdServiceCrashed(let service, let exitCode):
            return "launchd-service-\(service)-crashed-exit-\(exitCode)"
        case .launchdServiceThrottled(let service):
            return "launchd-service-\(service)-throttled"
        case .hostProxyListenerMismatch(let port, let listeners):
            return "host-proxy-listener-mismatch-port-\(port)-listeners-\(listeners)"
        case .hostProxyListenerScanUnavailable:
            return "host-proxy-listener-scan-unavailable"
        case .hostProxyListenerScanFailed(let port, let exitCode):
            return "host-proxy-listener-scan-failed-port-\(port)-exit-\(exitCode)"
        case .hostProxyConfigInvalid:
            return "host-proxy-config-invalid"
        case .httpProbeTimedOut(let target):
            return "http-probe-\(target)-timed-out"
        case .httpProbeConnectionRefused(let target):
            return "http-probe-\(target)-connection-refused"
        case .containerExited(let service, let exitCode):
            return "container-\(service)-exited-code-\(exitCode)"
        case .containerRestartLoop(let service):
            return "container-\(service)-restart-loop"
        case .vitalDBObservationStale:
            return "vitaldb-observation-stale"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func parseProxyPortInUse(_ rawValue: String) -> RuntimeFailureReason? {
        let prefix = "proxy-port-"
        let marker = "-in-use-by-"
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let portText = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        guard let port = Int(portText) else {
            return nil
        }
        return .proxyPortInUse(port: port, listeners: String(rawValue[markerRange.upperBound...]))
    }

    private static func parseContainerService(_ rawValue: String) -> RuntimeFailureReason? {
        let prefix = "container-service-"
        let marker = "-state-"
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let service = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        return .containerService(service: String(service), state: String(rawValue[markerRange.upperBound...]))
    }

    private static func parseVitalDBAnomaly(_ rawValue: String) -> RuntimeFailureReason? {
        let prefix = "vitaldb-anomaly-"
        let marker = "-subject-"
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let kind = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        return .vitalDBAnomaly(kind: String(kind), subject: String(rawValue[markerRange.upperBound...]))
    }

    private static func parseLaunchdServiceCrashed(_ rawValue: String) -> RuntimeFailureReason? {
        parseServiceIntValue(
            rawValue,
            prefix: "launchd-service-",
            marker: "-crashed-exit-",
            build: RuntimeFailureReason.launchdServiceCrashed
        )
    }

    private static func parseLaunchdServiceThrottled(_ rawValue: String) -> RuntimeFailureReason? {
        parseServiceValue(
            rawValue,
            prefix: "launchd-service-",
            suffix: "-throttled",
            build: RuntimeFailureReason.launchdServiceThrottled
        )
    }

    private static func parseHostProxyListenerMismatch(_ rawValue: String) -> RuntimeFailureReason? {
        let prefix = "host-proxy-listener-mismatch-port-"
        let marker = "-listeners-"
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let portText = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        guard let port = Int(portText) else {
            return nil
        }
        return .hostProxyListenerMismatch(port: port, listeners: String(rawValue[markerRange.upperBound...]))
    }

    private static func parseHostProxyListenerScanFailed(_ rawValue: String) -> RuntimeFailureReason? {
        parseIntPair(
            rawValue,
            prefix: "host-proxy-listener-scan-failed-port-",
            marker: "-exit-",
            build: RuntimeFailureReason.hostProxyListenerScanFailed
        )
    }

    private static func parseHTTPProbeTimedOut(_ rawValue: String) -> RuntimeFailureReason? {
        parseServiceValue(
            rawValue,
            prefix: "http-probe-",
            suffix: "-timed-out",
            build: RuntimeFailureReason.httpProbeTimedOut
        )
    }

    private static func parseHTTPProbeConnectionRefused(_ rawValue: String) -> RuntimeFailureReason? {
        parseServiceValue(
            rawValue,
            prefix: "http-probe-",
            suffix: "-connection-refused",
            build: RuntimeFailureReason.httpProbeConnectionRefused
        )
    }

    private static func parseContainerExited(_ rawValue: String) -> RuntimeFailureReason? {
        parseServiceIntValue(
            rawValue,
            prefix: "container-",
            marker: "-exited-code-",
            build: RuntimeFailureReason.containerExited
        )
    }

    private static func parseContainerRestartLoop(_ rawValue: String) -> RuntimeFailureReason? {
        parseServiceValue(
            rawValue,
            prefix: "container-",
            suffix: "-restart-loop",
            build: RuntimeFailureReason.containerRestartLoop
        )
    }

    private static func parseServiceValue(
        _ rawValue: String,
        prefix: String,
        suffix: String,
        build: (String) -> RuntimeFailureReason
    ) -> RuntimeFailureReason? {
        guard rawValue.hasPrefix(prefix), rawValue.hasSuffix(suffix) else {
            return nil
        }
        let start = rawValue.index(rawValue.startIndex, offsetBy: prefix.count)
        let end = rawValue.index(rawValue.endIndex, offsetBy: -suffix.count)
        guard start < end else {
            return nil
        }
        return build(String(rawValue[start..<end]))
    }

    private static func parseServiceIntValue(
        _ rawValue: String,
        prefix: String,
        marker: String,
        build: (String, Int) -> RuntimeFailureReason
    ) -> RuntimeFailureReason? {
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let service = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        guard let value = Int(rawValue[markerRange.upperBound...]) else {
            return nil
        }
        return build(String(service), value)
    }

    private static func parseIntPair(
        _ rawValue: String,
        prefix: String,
        marker: String,
        build: (Int, Int) -> RuntimeFailureReason
    ) -> RuntimeFailureReason? {
        guard rawValue.hasPrefix(prefix),
              let markerRange = rawValue.range(of: marker) else {
            return nil
        }
        let firstText = rawValue[rawValue.index(rawValue.startIndex, offsetBy: prefix.count)..<markerRange.lowerBound]
        let secondText = rawValue[markerRange.upperBound...]
        guard let first = Int(firstText),
              let second = Int(secondText) else {
            return nil
        }
        return build(first, second)
    }
}

public extension RuntimeFailureReason {
    var domainError: RuntimeDomainError {
        RuntimeDomainError(self)
    }

    var domainCategory: RuntimeDomainErrorCategory {
        if let vmError {
            return RuntimeDomainErrorCategory(vmError.category)
        }
        switch self {
        case .missingVMBin, .missingProxyRunner, .missingRootfsBase, .missingVMDisk:
            return .installation
        case .vmService:
            return .vmLifecycle
        case .proxyService, .hostProxyHTTP, .proxyPortInUse:
            return .hostProxy
        case .guestLogSyncService, .watchdogService, .runtimeStatusDocumentMissing, .runtimeStatusDocumentStale,
             .runtimeStatusDocumentInvalid, .observabilityEventStoreUnavailable, .observabilityEventStoreCorrupt,
             .containerObservationMissing, .containerObservationReadFailed:
            return .observability
        case .guestRuntimeStateInvalid:
            return .guestAgent
        case .vmLifecycleDocumentInvalid, .vmLifecycleDocumentStale,
             .vmPidFileStale, .vmProcessExited, .launchdServiceCrashed, .launchdServiceThrottled:
            return .vmLifecycle
        case .hostProxyListenerMismatch, .hostProxyListenerScanUnavailable,
             .hostProxyListenerScanFailed, .hostProxyConfigInvalid:
            return .hostProxy
        case .httpProbeTimedOut, .httpProbeConnectionRefused:
            return .guestNetworking
        case .containerExited, .containerRestartLoop:
            return .container
        case .redisUIHTTP, .swaggerUIHTTP:
            return .auxiliaryUI
        case .guestHTTP, .guestHTTPProbeFailed:
            return .guestNetworking
        case .guestRuntimeStateStale:
            return .guestAgent
        case .guestBootstrapResultMissing, .guestBootstrapResultUnavailable,
             .guestBootstrapMissingRuntimePackages, .guestBootstrapFailed:
            return .guestBootstrap
        case .auditProxyHTTP, .containerService:
            return .container
        case .vitalDBAnomaly, .vitalDBObservationMissing, .vitalDBObservationReadFailed, .vitalDBObservationStale:
            return .vitalDB
        case .unknown:
            return .unknown
        }
    }

    var domainSeverity: RuntimeDomainErrorSeverity {
        switch self {
        case .redisUIHTTP, .swaggerUIHTTP, .guestLogSyncService, .watchdogService, .guestRuntimeStateStale,
             .runtimeStatusDocumentStale, .observabilityEventStoreUnavailable,
             .vmLifecycleDocumentStale, .vmPidFileStale, .hostProxyListenerScanUnavailable,
             .hostProxyListenerScanFailed,
             .httpProbeTimedOut, .httpProbeConnectionRefused, .guestHTTPProbeFailed,
             .containerObservationMissing, .containerObservationReadFailed,
             .vitalDBObservationMissing, .vitalDBObservationReadFailed, .vitalDBObservationStale:
            return .warning
        case .vitalDBAnomaly(let kind, _):
            return warningOnlyVitalDBAnomalyKinds.contains(kind) ? .warning : .critical
        case .unknown(let value):
            return value.hasPrefix("vm-") ? .critical : .warning
        default:
            return .critical
        }
    }

    var recoveryAction: RuntimeDomainRecoveryAction {
        if let vmError {
            return RuntimeDomainRecoveryAction(vmError.recoveryAction)
        }
        switch self {
        case .missingVMBin, .missingProxyRunner, .missingRootfsBase, .missingVMDisk:
            return .installRuntime
        case .vmService:
            return .restartVMService
        case .proxyService, .hostProxyHTTP:
            return .restartProxyService
        case .watchdogService:
            return .restartWatchdogService
        case .guestLogSyncService:
            return .inspectLogs
        case .runtimeStatusDocumentMissing, .runtimeStatusDocumentStale, .runtimeStatusDocumentInvalid,
             .observabilityEventStoreUnavailable, .observabilityEventStoreCorrupt,
             .containerObservationMissing, .containerObservationReadFailed:
            return .inspectLogs
        case .guestRuntimeStateInvalid:
            return .restartGuestAgent
        case .vmPidFileStale, .vmProcessExited, .launchdServiceCrashed, .launchdServiceThrottled:
            return .restartVMService
        case .vmLifecycleDocumentInvalid, .vmLifecycleDocumentStale:
            return .inspectLogs
        case .hostProxyListenerMismatch:
            return .freeProxyPort
        case .hostProxyListenerScanUnavailable, .hostProxyListenerScanFailed:
            return .inspectLogs
        case .hostProxyConfigInvalid:
            return .repairProxyConfiguration
        case .httpProbeTimedOut, .httpProbeConnectionRefused:
            return .waitForGuest
        case .containerExited, .containerRestartLoop:
            return .restartContainerServices
        case .redisUIHTTP, .swaggerUIHTTP:
            return .inspectLogs
        case .guestHTTP, .guestHTTPProbeFailed:
            return .waitForGuest
        case .guestRuntimeStateStale:
            return .restartGuestAgent
        case .auditProxyHTTP, .containerService:
            return .restartContainerServices
        case .vitalDBAnomaly, .vitalDBObservationMissing, .vitalDBObservationReadFailed, .vitalDBObservationStale:
            return .inspectVitalDBObservation
        case .proxyPortInUse:
            return .freeProxyPort
        case .guestBootstrapResultMissing:
            return .waitForGuest
        case .guestBootstrapResultUnavailable:
            return .inspectLogs
        case .guestBootstrapMissingRuntimePackages, .guestBootstrapFailed:
            return .repairGuestBootstrap
        case .unknown:
            return .inspectLogs
        }
    }

    var requiresDataPreservationBeforeRecovery: Bool {
        recoveryAction == .backupAndRecreateVM
    }

    private var vmError: RuntimeVMError? {
        switch self {
        case .vmLifecycleDocumentInvalid, .vmLifecycleDocumentStale:
            return nil
        default:
            break
        }
        let parsed = RuntimeVMError(rawValue: rawValue)
        if case .unknown(let value) = parsed {
            return value.hasPrefix("vm-") ? parsed : nil
        }
        return parsed
    }

    private var warningOnlyVitalDBAnomalyKinds: Set<String> {
        ["duplicate-ip", "offline", "stale-recorder"]
    }
}

private extension RuntimeDomainErrorCategory {
    init(_ category: RuntimeVMErrorCategory) {
        switch category {
        case .installation:
            self = .installation
        case .lifecycle:
            self = .vmLifecycle
        case .networking:
            self = .guestNetworking
        case .guestAgent:
            self = .guestAgent
        case .guestBootstrap:
            self = .guestBootstrap
        case .guestStorage:
            self = .guestStorage
        case .configuration:
            self = .configuration
        case .hostResources:
            self = .hostResources
        case .unknown:
            self = .unknown
        }
    }
}

private extension RuntimeDomainRecoveryAction {
    init(_ action: RuntimeVMRecoveryAction) {
        switch action {
        case .installRuntime:
            self = .installRuntime
        case .restartVMService:
            self = .restartVMService
        case .waitForGuest:
            self = .waitForGuest
        case .restartGuestAgent:
            self = .restartGuestAgent
        case .repairGuestBootstrap:
            self = .repairGuestBootstrap
        case .backupAndRecreateVM:
            self = .backupAndRecreateVM
        case .fixConfiguration:
            self = .fixConfiguration
        case .freeHostResources:
            self = .freeHostResources
        case .inspectLogs:
            self = .inspectLogs
        }
    }
}

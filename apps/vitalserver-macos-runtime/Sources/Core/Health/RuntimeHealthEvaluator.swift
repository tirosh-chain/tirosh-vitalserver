import Contracts
import Foundation

public struct RuntimeHealthInput: Equatable {
    public let vmExecutable: Bool
    public let proxyExecutable: Bool
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmIP: String?
    public let proxyPort: Int
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let guestRuntimeStateFresh: Bool
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let containerObservation: RuntimeContainerObservation?
    public let vitalDBObservation: VitalDBObservationDocument?
    public let vmDiagnosticErrors: [RuntimeVMError]
    public let proxyPortFailureReasons: [RuntimeFailureReason]
    public let guestBootstrapFailureReason: RuntimeFailureReason?

    public init(
        vmExecutable: Bool,
        proxyExecutable: Bool,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmIP: String?,
        proxyPort: Int,
        hostProxyHTTP: String,
        guestHTTP: String,
        guestRuntimeStateFresh: Bool = true,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil,
        vmDiagnosticErrors: [RuntimeVMError] = [],
        proxyPortFailureReasons: [RuntimeFailureReason] = [],
        guestBootstrapFailureReason: RuntimeFailureReason? = nil
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmIP = vmIP
        self.proxyPort = proxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.guestRuntimeStateFresh = guestRuntimeStateFresh
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.containerObservation = containerObservation
        self.vitalDBObservation = vitalDBObservation
        self.vmDiagnosticErrors = vmDiagnosticErrors
        self.proxyPortFailureReasons = proxyPortFailureReasons
        self.guestBootstrapFailureReason = guestBootstrapFailureReason
    }
}

public enum RuntimeHealthEvaluator {
    public static func evaluate(_ input: RuntimeHealthInput) -> RuntimeHealthSnapshot {
        let vmErrors = evaluateVMErrors(input)
        var failureReasons = vmErrors.map(RuntimeFailureReason.init(vmError:))

        if !input.proxyExecutable {
            failureReasons.append(.missingProxyRunner)
        }
        if input.proxyService != .loaded {
            failureReasons.append(.proxyService(input.proxyService.rawValue))
        }
        if input.watchdogService != .loaded {
            failureReasons.append(.watchdogService(input.watchdogService.rawValue))
        }
        if !isSuccessfulHTTPStatus(input.hostProxyHTTP) {
            failureReasons.append(.hostProxyHTTP(input.hostProxyHTTP))
            failureReasons.append(contentsOf: input.proxyPortFailureReasons)
        }
        if let containerObservation = input.containerObservation,
           !isSuccessfulHTTPStatus(containerObservation.auditProxyHTTP) {
            failureReasons.append(.auditProxyHTTP(containerObservation.auditProxyHTTP))
        }
        failureReasons.append(contentsOf: RuntimeObservationHealthPolicy.failureReasons(
            containerObservation: input.containerObservation,
            vitalDBObservation: input.vitalDBObservation
        ))

        return RuntimeHealthSnapshot(
            vmExecutable: input.vmExecutable,
            proxyExecutable: input.proxyExecutable,
            rootfsBase: input.rootfsBase,
            vmDisk: input.vmDisk,
            vmService: input.vmService,
            proxyService: input.proxyService,
            watchdogService: input.watchdogService,
            vmState: vmState(input, errors: vmErrors),
            vmErrors: vmErrors,
            vmIP: input.vmIP,
            proxyPort: input.proxyPort,
            hostProxyHTTP: input.hostProxyHTTP,
            guestHTTP: input.guestHTTP,
            redisUIHTTP: input.redisUIHTTP,
            swaggerUIHTTP: input.swaggerUIHTTP,
            containerObservation: input.containerObservation,
            vitalDBObservation: input.vitalDBObservation,
            failureReasons: failureReasons
        )
    }

    private static func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private static func evaluateVMErrors(_ input: RuntimeHealthInput) -> [RuntimeVMError] {
        var errors: [RuntimeVMError] = []
        if !input.vmExecutable {
            errors.append(.missingExecutable)
        }
        if input.rootfsBase != .present {
            errors.append(.missingRootfsBase)
        }
        if input.vmDisk != .present {
            errors.append(.missingDisk)
        }
        if input.vmService != .loaded {
            errors.append(.serviceNotLoaded(input.vmService.rawValue))
        }
        if input.vmIP == nil {
            errors.append(.missingIPAddress)
        }
        if !isSuccessfulHTTPStatus(input.guestHTTP), input.guestHTTP != "missing-vm-ip" {
            errors.append(.guestHTTP(input.guestHTTP))
            if let guestBootstrapFailureReason = input.guestBootstrapFailureReason {
                errors.append(vmError(for: guestBootstrapFailureReason))
            }
        }
        if !input.guestRuntimeStateFresh {
            errors.append(.runtimeStateStale)
        }
        return uniqueErrors(errors + input.vmDiagnosticErrors)
    }

    private static func vmError(for failureReason: RuntimeFailureReason) -> RuntimeVMError {
        switch failureReason {
        case .guestBootstrapMissingRuntimePackages:
            return .guestBootstrapMissingRuntimePackages
        case .guestBootstrapFailed:
            return .guestBootstrapFailed
        default:
            return .unknown(failureReason.rawValue)
        }
    }

    private static func vmState(_ input: RuntimeHealthInput, errors: [RuntimeVMError]) -> RuntimeVMState {
        if errors.contains(.missingExecutable) {
            return .notInstalled
        }
        if errors.contains(.missingRootfsBase)
            || errors.contains(.missingDisk)
            || errors.contains(.diskAttachmentInvalid)
            || errors.contains(.guestFilesystemError)
            || errors.contains(.guestFilesystemReadOnly)
            || errors.contains(.guestDiskIO) {
            return .failed
        }
        if errors.contains(where: { error in
            if case .serviceNotLoaded = error {
                return true
            }
            return false
        }) {
            return .stopped
        }
        if errors.contains(.runtimeStateStale) {
            return .stale
        }
        if errors.contains(.missingIPAddress) {
            return .starting
        }
        if !errors.contains(where: { error in
            if case .guestHTTP = error {
                return true
            }
            return false
        }) {
            return .running
        }
        if input.guestHTTP == "bootstrap-pending" || input.guestHTTP == "missing-vm-ip" {
            return .starting
        }
        return .unreachable
    }

    private static func uniqueErrors(_ errors: [RuntimeVMError]) -> [RuntimeVMError] {
        var result: [RuntimeVMError] = []
        for error in errors where !result.contains(error) {
            result.append(error)
        }
        return result
    }
}

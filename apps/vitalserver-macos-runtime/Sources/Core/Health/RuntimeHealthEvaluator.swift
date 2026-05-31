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
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let vmIP: String?
    public let proxyPort: Int
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let guestRuntimeStatePresent: Bool
    public let guestRuntimeStateFresh: Bool
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let containerObservation: RuntimeContainerObservation?
    public let vitalDBObservation: VitalDBObservationDocument?
    public let reportedVMErrors: [RuntimeVMError]
    public let configurationFailureReasons: [RuntimeFailureReason]
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
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        vmIP: String?,
        proxyPort: Int,
        hostProxyHTTP: String,
        guestHTTP: String,
        guestRuntimeStatePresent: Bool,
        guestRuntimeStateFresh: Bool,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil,
        reportedVMErrors: [RuntimeVMError] = [],
        configurationFailureReasons: [RuntimeFailureReason] = [],
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
        self.vmLifecycle = vmLifecycle
        self.vmIP = vmIP
        self.proxyPort = proxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.guestRuntimeStatePresent = guestRuntimeStatePresent
        self.guestRuntimeStateFresh = guestRuntimeStateFresh
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.containerObservation = containerObservation
        self.vitalDBObservation = vitalDBObservation
        self.reportedVMErrors = reportedVMErrors
        self.configurationFailureReasons = configurationFailureReasons
        self.proxyPortFailureReasons = proxyPortFailureReasons
        self.guestBootstrapFailureReason = guestBootstrapFailureReason
    }
}

public enum RuntimeHealthEvaluator {
    public static func evaluate(_ input: RuntimeHealthInput) -> RuntimeHealthSnapshot {
        let vmHealth = RuntimeVMHealthPolicy.evaluate(input)
        let vmErrors = vmHealth.vmErrors
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
        failureReasons.append(contentsOf: input.configurationFailureReasons)
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
            vmLifecycle: input.vmLifecycle,
            vmState: vmHealth.vmState,
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

}

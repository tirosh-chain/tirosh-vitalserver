import Foundation

public struct RuntimeHealthSnapshot: Equatable {
    public let vmExecutable: Bool
    public let proxyExecutable: Bool
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let vmState: RuntimeVMState
    public let vmErrors: [RuntimeVMError]
    public let vmIP: String?
    public let proxyPort: Int
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let containerObservation: RuntimeContainerObservation?
    public let vitalDBObservation: VitalDBObservationDocument?
    public let failureReasons: [RuntimeFailureReason]

    public init(
        vmExecutable: Bool,
        proxyExecutable: Bool,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        vmState: RuntimeVMState,
        vmErrors: [RuntimeVMError] = [],
        vmIP: String?,
        proxyPort: Int,
        hostProxyHTTP: String,
        guestHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        containerObservation: RuntimeContainerObservation? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil,
        failureReasons: [RuntimeFailureReason]
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmLifecycle = vmLifecycle
        self.vmState = vmState
        self.vmErrors = vmErrors
        self.vmIP = vmIP
        self.proxyPort = proxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.containerObservation = containerObservation
        self.vitalDBObservation = vitalDBObservation
        self.failureReasons = failureReasons
    }
}

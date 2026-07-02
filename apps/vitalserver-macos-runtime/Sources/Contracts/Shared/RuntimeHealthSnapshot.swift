import Foundation

public struct RuntimeHealthSnapshot: Equatable {
    public let vmExecutable: RuntimeFileState
    public let proxyExecutable: RuntimeFileState
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let vmState: RuntimeVMState
    public let vmErrors: [RuntimeVMError]
    public let vmIP: String?
    public let proxyPort: Int?
    public let proxyPortReadState: RuntimeProxyPortReadState
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]>
    public let vitalDBObservation: VitalDBObservationDocument?
    public let failureReasons: [RuntimeFailureReason]

    public init(
        vmExecutable: RuntimeFileState,
        proxyExecutable: RuntimeFileState,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        vmState: RuntimeVMState,
        vmErrors: [RuntimeVMError] = [],
        vmIP: String?,
        proxyPort: Int?,
        proxyPortReadState: RuntimeProxyPortReadState? = nil,
        hostProxyHTTP: String,
        guestHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported,
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
        self.proxyPortReadState = proxyPortReadState ?? .observed(proxyPort)
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.guestServiceStatuses = guestServiceStatuses
        self.vitalDBObservation = vitalDBObservation
        self.failureReasons = failureReasons
    }
}

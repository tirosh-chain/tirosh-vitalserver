import Contracts
import Foundation

public struct RuntimeHealthInput: Equatable {
    public let vmExecutable: RuntimeFileState
    public let proxyExecutable: RuntimeFileState
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let guestReadiness: RuntimeGuestReadinessInput
    public let proxyPort: Int?
    public let proxyPortReadState: RuntimeProxyPortReadState
    public let hostProxyHTTP: String
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]>
    public let vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument>
    public let reportedVMErrors: [RuntimeVMError]
    public let configurationFailureReasons: [RuntimeFailureReason]
    public let proxyPortFailureReasons: [RuntimeFailureReason]
    public let guestBootstrapAssessment: GuestBootstrapAssessment

    public init(
        vmExecutable: RuntimeFileState,
        proxyExecutable: RuntimeFileState,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        guestReadiness: RuntimeGuestReadinessInput,
        proxyPort: Int?,
        proxyPortReadState: RuntimeProxyPortReadState,
        hostProxyHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported,
        vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument>,
        reportedVMErrors: [RuntimeVMError] = [],
        configurationFailureReasons: [RuntimeFailureReason] = [],
        proxyPortFailureReasons: [RuntimeFailureReason] = [],
        guestBootstrapAssessment: GuestBootstrapAssessment
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmLifecycle = vmLifecycle
        self.guestReadiness = guestReadiness
        self.proxyPort = proxyPort
        self.proxyPortReadState = proxyPortReadState
        self.hostProxyHTTP = hostProxyHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.guestServiceStatuses = guestServiceStatuses
        self.vitalDBObservation = vitalDBObservation
        self.reportedVMErrors = reportedVMErrors
        self.configurationFailureReasons = configurationFailureReasons
        self.proxyPortFailureReasons = proxyPortFailureReasons
        self.guestBootstrapAssessment = guestBootstrapAssessment
    }
}

public enum RuntimeHealthEvaluator {
    public static func evaluate(_ input: RuntimeHealthInput) -> RuntimeHealthSnapshot {
        let vmHealth = RuntimeVMHealthPolicy.evaluate(input)
        let vmErrors = vmHealth.vmErrors
        var failureReasons = vmErrors.map(RuntimeFailureReason.init(vmError:))

        if input.proxyExecutable != .executable {
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
        failureReasons.append(contentsOf: RuntimeObservationHealthPolicy.failureReasons(
            guestServiceStatuses: input.guestServiceStatuses
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
            vmIP: input.guestReadiness.vmIP,
            proxyPort: input.proxyPort,
            proxyPortReadState: input.proxyPortReadState,
            hostProxyHTTP: input.hostProxyHTTP,
            guestHTTP: input.guestReadiness.guestHTTPStatusText,
            redisUIHTTP: input.redisUIHTTP,
            swaggerUIHTTP: input.swaggerUIHTTP,
            guestServiceStatuses: input.guestServiceStatuses,
            vitalDBObservation: input.vitalDBObservation.observedValue,
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

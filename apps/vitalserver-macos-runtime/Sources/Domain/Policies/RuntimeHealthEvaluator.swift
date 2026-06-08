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
    public let guestRuntimeState: RuntimeGuestRuntimeStateInput
    public let proxyPort: Int?
    public let proxyPortReadState: RuntimeProxyPortReadState
    public let hostProxyHTTP: String
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let containerObservation: RuntimeObservationInput<RuntimeContainerObservation>
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
        guestRuntimeState: RuntimeGuestRuntimeStateInput,
        proxyPort: Int?,
        proxyPortReadState: RuntimeProxyPortReadState,
        hostProxyHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        containerObservation: RuntimeObservationInput<RuntimeContainerObservation>,
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
        self.guestRuntimeState = guestRuntimeState
        self.proxyPort = proxyPort
        self.proxyPortReadState = proxyPortReadState
        self.hostProxyHTTP = hostProxyHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.containerObservation = containerObservation
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
        if let containerObservation = input.containerObservation.observedValue,
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
            vmIP: input.guestRuntimeState.vmIP,
            proxyPort: input.proxyPort,
            proxyPortReadState: input.proxyPortReadState,
            hostProxyHTTP: input.hostProxyHTTP,
            guestHTTP: input.guestRuntimeState.guestHTTPStatusText,
            redisUIHTTP: input.redisUIHTTP,
            swaggerUIHTTP: input.swaggerUIHTTP,
            containerObservation: input.containerObservation.observedValue,
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

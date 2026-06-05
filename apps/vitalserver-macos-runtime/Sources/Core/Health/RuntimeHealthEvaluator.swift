import Contracts
import Foundation

public enum RuntimeGuestHTTPStatusInput: Equatable {
    case reportedStatus(String)
    case missing
    case probeFailed(String)

    public var statusText: String {
        switch self {
        case .reportedStatus(let value):
            return value
        case .missing:
            return RuntimeHTTPStatusText.missingGuestHTTP
        case .probeFailed(let value):
            return value
        }
    }

    public var isSuccessful: Bool {
        guard case .reportedStatus(let value) = self,
              let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}

public enum RuntimeGuestRuntimeStateInput: Equatable {
    case fresh(vmIP: String?, guestHTTP: RuntimeGuestHTTPStatusInput)
    case missing
    case invalid
    case stale

    public var vmIP: String? {
        guard case .fresh(let vmIP, _) = self else {
            return nil
        }
        return vmIP
    }

    public var guestHTTPStatusText: String {
        guard case .fresh(_, let guestHTTP) = self else {
            return RuntimeHTTPStatusText.missingVMIP
        }
        return guestHTTP.statusText
    }
}

public enum RuntimeObservationInput<Observation: Equatable & Sendable>: Equatable, Sendable {
    case notReported
    case missing
    case readFailed(String)
    case loaded(Observation)

    public var observedValue: Observation? {
        guard case .loaded(let value) = self else {
            return nil
        }
        return value
    }
}

public struct RuntimeHealthInput: Equatable {
    public let vmExecutable: Bool
    public let proxyExecutable: Bool
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let guestRuntimeState: RuntimeGuestRuntimeStateInput
    public let proxyPort: Int
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
        vmExecutable: Bool,
        proxyExecutable: Bool,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        watchdogService: RuntimeServiceState,
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        guestRuntimeState: RuntimeGuestRuntimeStateInput,
        proxyPort: Int,
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

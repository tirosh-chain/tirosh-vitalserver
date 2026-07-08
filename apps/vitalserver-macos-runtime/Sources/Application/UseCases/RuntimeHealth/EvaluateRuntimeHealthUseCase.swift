import Contracts
import Domain
import Foundation

public struct RuntimeHealthObservation {
    public let vmExecutable: RuntimeFileState
    public let proxyExecutable: RuntimeFileState
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let watchdogService: RuntimeServiceState
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let guestAddressRead: RuntimeGuestAddressReadResult
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
        vmLifecycle: RuntimeVMLifecycleDocument?,
        guestAddressRead: RuntimeGuestAddressReadResult = .notReported,
        guestReadiness: RuntimeGuestReadinessInput,
        proxyPort: Int?,
        proxyPortReadState: RuntimeProxyPortReadState,
        hostProxyHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        guestServiceStatuses: RuntimeObservationInput<[RuntimeGuestControlServiceStatus]> = .notReported,
        vitalDBObservation: RuntimeObservationInput<VitalDBObservationDocument>,
        reportedVMErrors: [RuntimeVMError],
        configurationFailureReasons: [RuntimeFailureReason],
        proxyPortFailureReasons: [RuntimeFailureReason],
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
        self.vmLifecycle = vmLifecycle
        self.guestAddressRead = guestAddressRead
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
        self.guestBootstrapResult = guestBootstrapResult
        self.observedAt = observedAt
        self.guestBootstrapFreshnessGraceSeconds = guestBootstrapFreshnessGraceSeconds
    }
}

public struct RuntimeGuestReadinessInputPlan: Equatable {
    public let state: RuntimeGuestReadinessInput
    public let failureReasons: [RuntimeFailureReason]

    public init(
        state: RuntimeGuestReadinessInput,
        failureReasons: [RuntimeFailureReason] = []
    ) {
        self.state = state
        self.failureReasons = failureReasons
    }
}

public struct EvaluateRuntimeHealthUseCase {
    public init() {}

    public func observation(from reads: RuntimeHealthObservationReads) -> RuntimeHealthObservation {
        let guestReadinessInput = guestReadinessInputPlan(
            guestControlReadiness: reads.guestControlReadiness
        )
        let vmLifecycle = vmLifecycleObservation(
            from: reads.vmLifecycleLoadResult,
            observedAt: reads.observedAt
        )

        return RuntimeHealthObservation(
            vmExecutable: reads.vmExecutable,
            proxyExecutable: reads.proxyExecutable,
            rootfsBase: reads.rootfsBase,
            vmDisk: reads.vmDisk,
            vmService: reads.vmService,
            proxyService: reads.proxyService,
            watchdogService: reads.watchdogService,
            vmLifecycle: vmLifecycle.document,
            guestAddressRead: reads.guestAddressRead,
            guestReadiness: guestReadinessInput.state,
            proxyPort: reads.proxyPortReadState.port,
            proxyPortReadState: reads.proxyPortReadState,
            hostProxyHTTP: httpStatusText(reads.hostProxyHTTP),
            redisUIHTTP: httpStatusText(reads.redisUIHTTP),
            swaggerUIHTTP: httpStatusText(reads.swaggerUIHTTP),
            guestServiceStatuses: reads.guestServiceStatuses,
            vitalDBObservation: reads.vitalDBObservation,
            reportedVMErrors: [],
            configurationFailureReasons: reads.proxyPortReadState.failureReasons
                + vmLifecycle.failureReasons
                + guestReadinessInput.failureReasons,
            proxyPortFailureReasons: proxyPortFailureReasons(reads.proxyListenerObservation),
            guestBootstrapResult: reads.guestBootstrapResult,
            observedAt: reads.observedAt,
            guestBootstrapFreshnessGraceSeconds: reads.guestBootstrapFreshnessGraceSeconds
        )
    }

    public func guestReadinessInputPlan(
        guestControlReadiness: RuntimeGuestControlReadinessRead = .notReported
    ) -> RuntimeGuestReadinessInputPlan {
        switch guestControlReadiness {
        case .notReported:
            return RuntimeGuestReadinessInputPlan(state: .notReported)
        case .loaded(let vmIP, let readiness):
            return RuntimeGuestReadinessInputPlan(
                state: .reported(
                    vmIP: vmIP,
                    guestHTTP: guestHTTPStatus(readiness)
                )
            )
        case .failed(let vmIP, let message):
            return RuntimeGuestReadinessInputPlan(
                state: .reported(
                    vmIP: vmIP,
                    guestHTTP: .probeFailed("guestControl=\(message)")
                )
            )
        }
    }

    private func guestHTTPStatus(_ readiness: RuntimeGuestControlReadiness) -> RuntimeGuestHTTPStatusInput {
        if readiness.status == "ready" {
            return .reportedStatus("200")
        }
        if let failureSummary = readiness.failureSummary {
            return .probeFailed("\(readiness.status):\(failureSummary)")
        }
        return .probeFailed(readiness.status)
    }

    public func httpStatusText(_ read: RuntimeHTTPProbeResult?) -> String {
        read?.statusText ?? RuntimeHTTPStatusText.missingProxyPort
    }

    public func hostProxyListenerFailureReasons(
        port: Int,
        scanResult: RuntimeHostProxyListenerScanResult,
        expectedNginxPID: RuntimeProxyNginxPIDReadResult
    ) -> [RuntimeFailureReason] {
        RuntimeHostProxyListenerPolicy.failureReasons(
            port: port,
            scanResult: scanResult,
            expectedNginxPID: expectedNginxPID
        )
    }

    public func snapshot(observation: RuntimeHealthObservation) -> RuntimeHealthSnapshot {
        RuntimeHealthEvaluator.evaluate(RuntimeHealthInput(
            vmExecutable: observation.vmExecutable,
            proxyExecutable: observation.proxyExecutable,
            rootfsBase: observation.rootfsBase,
            vmDisk: observation.vmDisk,
            vmService: observation.vmService,
            proxyService: observation.proxyService,
            watchdogService: observation.watchdogService,
            vmLifecycle: observation.vmLifecycle,
            guestAddressRead: observation.guestAddressRead,
            guestReadiness: observation.guestReadiness,
            proxyPort: observation.proxyPort,
            proxyPortReadState: observation.proxyPortReadState,
            hostProxyHTTP: observation.hostProxyHTTP,
            redisUIHTTP: observation.redisUIHTTP,
            swaggerUIHTTP: observation.swaggerUIHTTP,
            guestServiceStatuses: observation.guestServiceStatuses,
            vitalDBObservation: observation.vitalDBObservation,
            reportedVMErrors: observation.reportedVMErrors,
            configurationFailureReasons: observation.configurationFailureReasons,
            proxyPortFailureReasons: observation.proxyPortFailureReasons,
            guestBootstrapAssessment: GuestBootstrapEvaluator.assessCurrentBoot(
                observation.guestBootstrapResult,
                currentBootID: observation.vmLifecycle?.bootID,
                now: observation.observedAt,
                graceSeconds: observation.guestBootstrapFreshnessGraceSeconds
            )
        ))
    }

    private func vmLifecycleObservation(
        from loadResult: RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument>,
        observedAt: Date
    ) -> RuntimeVMLifecycleObservation {
        switch loadResult {
        case .missing:
            return RuntimeVMLifecycleObservation(document: nil, failureReasons: [])
        case .failed:
            return RuntimeVMLifecycleObservation(document: nil, failureReasons: [.vmLifecycleDocumentInvalid])
        case .loaded(let document):
            guard let deadlineAt = document.deadlineAt else {
                return RuntimeVMLifecycleObservation(document: document, failureReasons: [])
            }
            guard let deadline = ISO8601DateFormatter().date(from: deadlineAt) else {
                return RuntimeVMLifecycleObservation(document: document, failureReasons: [.vmLifecycleDocumentInvalid])
            }
            guard observedAt <= deadline || !(document.state == .starting || document.state == .bootstrapping) else {
                return RuntimeVMLifecycleObservation(document: document, failureReasons: [.vmLifecycleDocumentStale])
            }
            return RuntimeVMLifecycleObservation(document: document, failureReasons: [])
        }
    }

    private func proxyPortFailureReasons(
        _ observation: RuntimeHostProxyListenerObservation?
    ) -> [RuntimeFailureReason] {
        guard let observation else {
            return []
        }
        return hostProxyListenerFailureReasons(
            port: observation.port,
            scanResult: observation.scanResult,
            expectedNginxPID: observation.expectedNginxPID
        )
    }
}

private struct RuntimeVMLifecycleObservation {
    let document: RuntimeVMLifecycleDocument?
    let failureReasons: [RuntimeFailureReason]
}

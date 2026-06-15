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
    public let guestRuntimeState: RuntimeGuestRuntimeStateInput
    public let loadedGuestRuntimeState: GuestRuntimeStateDocument?
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
        guestRuntimeState: RuntimeGuestRuntimeStateInput,
        loadedGuestRuntimeState: GuestRuntimeStateDocument?,
        proxyPort: Int?,
        proxyPortReadState: RuntimeProxyPortReadState,
        hostProxyHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        containerObservation: RuntimeObservationInput<RuntimeContainerObservation>,
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
        self.guestRuntimeState = guestRuntimeState
        self.loadedGuestRuntimeState = loadedGuestRuntimeState
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
        self.guestBootstrapResult = guestBootstrapResult
        self.observedAt = observedAt
        self.guestBootstrapFreshnessGraceSeconds = guestBootstrapFreshnessGraceSeconds
    }
}

public struct RuntimeGuestRuntimeStateInputPlan: Equatable {
    public let state: RuntimeGuestRuntimeStateInput
    public let failureReasons: [RuntimeFailureReason]

    public init(
        state: RuntimeGuestRuntimeStateInput,
        failureReasons: [RuntimeFailureReason] = []
    ) {
        self.state = state
        self.failureReasons = failureReasons
    }
}

public struct RuntimeComposeServicesReadResult: Equatable {
    public let state: RuntimeContainerServicesReadState
    public let services: [RuntimeContainerServiceObservation]
    public let readError: String?

    public init(
        state: RuntimeContainerServicesReadState,
        services: [RuntimeContainerServiceObservation],
        readError: String?
    ) {
        self.state = state
        self.services = services
        self.readError = readError
    }
}

public struct EvaluateRuntimeHealthUseCase {
    public init() {}

    public func observation(from reads: RuntimeHealthObservationReads) -> RuntimeHealthObservation {
        let guestRuntimeStateReadFailures = guestRuntimeStateReadFailureReasons(
            reads.guestRuntimeState.readIssue
        )
        let guestRuntimeStateInput = guestRuntimeStateInputPlan(
            freshState: reads.guestRuntimeState.freshState,
            loadedState: reads.guestRuntimeState.loadedState,
            readFailureReasons: guestRuntimeStateReadFailures
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
            guestRuntimeState: guestRuntimeStateInput.state,
            loadedGuestRuntimeState: reads.guestRuntimeState.loadedState,
            proxyPort: reads.proxyPortReadState.port,
            proxyPortReadState: reads.proxyPortReadState,
            hostProxyHTTP: httpStatusText(reads.hostProxyHTTP),
            redisUIHTTP: httpStatusText(reads.redisUIHTTP),
            swaggerUIHTTP: httpStatusText(reads.swaggerUIHTTP),
            containerObservation: .loaded(containerObservation(from: reads)),
            vitalDBObservation: vitalDBObservation(reads.guestRuntimeState),
            reportedVMErrors: reportedVMErrors(from: reads.guestRuntimeState.freshState?.diskHealth),
            configurationFailureReasons: reads.proxyPortReadState.failureReasons
                + guestRuntimeStateReadFailures
                + vmLifecycle.failureReasons
                + guestRuntimeStateInput.failureReasons,
            proxyPortFailureReasons: proxyPortFailureReasons(reads.proxyListenerObservation),
            guestBootstrapResult: reads.guestBootstrapResult,
            observedAt: reads.observedAt,
            guestBootstrapFreshnessGraceSeconds: reads.guestBootstrapFreshnessGraceSeconds
        )
    }

    public func guestRuntimeStateInputPlan(
        freshState: GuestRuntimeStateDocument?,
        loadedState: GuestRuntimeStateDocument?,
        readFailureReasons: [RuntimeFailureReason]
    ) -> RuntimeGuestRuntimeStateInputPlan {
        let assessment = RuntimeGuestRuntimeStatePolicy.inputAssessment(
            freshState: freshState,
            loadedState: loadedState,
            readFailureReasons: readFailureReasons
        )
        return RuntimeGuestRuntimeStateInputPlan(
            state: assessment.state,
            failureReasons: assessment.failureReasons
        )
    }

    public func reportedVMErrors(
        from diskHealth: GuestDiskHealthDocument?
    ) -> [RuntimeVMError] {
        RuntimeGuestRuntimeStatePolicy.reportedVMErrors(from: diskHealth)
    }

    public func httpStatusText(_ read: RuntimeHTTPProbeResult?) -> String {
        read?.statusText ?? RuntimeHTTPStatusText.missingProxyPort
    }

    public func composeServicesReadResult(
        freshState: GuestRuntimeStateDocument?,
        loadedState: GuestRuntimeStateDocument?,
        readFailureReasons: [RuntimeFailureReason]
    ) -> RuntimeComposeServicesReadResult {
        if let guestState = freshState {
            if let composeReadError = composeServicesProbeError(guestState) {
                return RuntimeComposeServicesReadResult(
                    state: .readFailed,
                    services: guestState.containerServices ?? [],
                    readError: composeReadError
                )
            }
            guard let services = guestState.containerServices else {
                return RuntimeComposeServicesReadResult(
                    state: .missing,
                    services: [],
                    readError: "container-services-missing"
                )
            }
            return RuntimeComposeServicesReadResult(
                state: .loaded,
                services: services,
                readError: nil
            )
        }
        if readFailureReasons.contains(where: \.isGuestRuntimeStateReadFailure)
            || readFailureReasons.contains(.guestRuntimeStateInvalid) {
            return RuntimeComposeServicesReadResult(
                state: .invalid,
                services: [],
                readError: "guest-runtime-state-invalid"
            )
        }
        if loadedState != nil {
            return RuntimeComposeServicesReadResult(
                state: .stale,
                services: [],
                readError: "guest-runtime-state-stale"
            )
        }
        return RuntimeComposeServicesReadResult(
            state: .missing,
            services: [],
            readError: "guest-runtime-state-missing"
        )
    }

    private func composeServicesProbeError(_ guestState: GuestRuntimeStateDocument) -> String? {
        guard let error = guestState.probeErrors?.first(where: { error in
            error.source == "docker compose ps"
        }) else {
            return nil
        }
        return "\(error.source): \(error.message)"
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
            guestRuntimeState: observation.guestRuntimeState,
            proxyPort: observation.proxyPort,
            proxyPortReadState: observation.proxyPortReadState,
            hostProxyHTTP: observation.hostProxyHTTP,
            redisUIHTTP: observation.redisUIHTTP,
            swaggerUIHTTP: observation.swaggerUIHTTP,
            containerObservation: observation.containerObservation,
            vitalDBObservation: observation.vitalDBObservation,
            reportedVMErrors: observation.reportedVMErrors,
            configurationFailureReasons: observation.configurationFailureReasons,
            proxyPortFailureReasons: observation.proxyPortFailureReasons,
            guestBootstrapAssessment: GuestBootstrapEvaluator.assessCurrentBoot(
                observation.guestBootstrapResult,
                guestState: observation.loadedGuestRuntimeState,
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

    private func containerObservation(from reads: RuntimeHealthObservationReads) -> RuntimeContainerObservation {
        let composeServices = composeServicesReadResult(
            freshState: reads.guestRuntimeState.freshState,
            loadedState: reads.guestRuntimeState.loadedState,
            readFailureReasons: guestRuntimeStateReadFailureReasons(reads.guestRuntimeState.readIssue)
        )
        let auditProxyHTTP: String
        let auditProxyStatus: RuntimeAuditProxyStatusDocument?
        let auditProxyStatusReadState: RuntimeAuditProxyStatusReadState
        let auditProxyStatusReadError: String?
        if let auditProxyStatusRead = reads.auditProxyStatus {
            auditProxyHTTP = auditProxyStatusRead.httpStatus
            auditProxyStatus = auditProxyStatusRead.document
            auditProxyStatusReadState = auditProxyStatusRead.readState
            auditProxyStatusReadError = auditProxyStatusRead.readError
        } else {
            auditProxyHTTP = RuntimeHTTPStatusText.missingProxyPort
            auditProxyStatus = nil
            auditProxyStatusReadState = .skippedMissingProxyPort
            auditProxyStatusReadError = RuntimeHTTPStatusText.missingProxyPort
        }
        return RuntimeContainerObservation(
            auditProxyHTTP: auditProxyHTTP,
            auditProxyStatus: auditProxyStatus,
            auditProxyStatusReadState: auditProxyStatusReadState,
            auditProxyStatusReadError: auditProxyStatusReadError,
            runtimeStateUpdatedAt: reads.guestRuntimeState.freshState?.updatedAt,
            runtimeStateFileUpdatedAt: reads.runtimeStateFileModifiedAt.updatedAt,
            runtimeStateFileMetadataReadState: reads.runtimeStateFileModifiedAt.readState,
            runtimeStateFileMetadataError: reads.runtimeStateFileModifiedAt.readError,
            containerLogsPresent: reads.containerLogsMetadata.present,
            containerLogsBytes: reads.containerLogsMetadata.bytes,
            containerLogsUpdatedAt: reads.containerLogsMetadata.updatedAt,
            containerLogsMetadataError: reads.containerLogsMetadata.error,
            composeServicesReadState: composeServices.state,
            composeServices: composeServices.services,
            composeServicesReadError: composeServices.readError
        )
    }

    private func vitalDBObservation(
        _ observation: RuntimeGuestRuntimeStateObservation
    ) -> RuntimeObservationInput<VitalDBObservationDocument> {
        guard let guestState = observation.freshState else {
            return .notReported
        }
        guard let vitalDBObservation = guestState.vitalDBObservation else {
            return .missing
        }
        return .loaded(vitalDBObservation)
    }

    private func guestRuntimeStateReadFailureReasons(
        _ issue: RuntimeGuestRuntimeStateReadIssue?
    ) -> [RuntimeFailureReason] {
        guard let issue else {
            return []
        }
        return [issue.failureReason]
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

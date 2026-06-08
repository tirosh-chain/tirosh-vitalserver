import Application
import Contracts
import Domain
import XCTest

final class EvaluateRuntimeHealthUseCaseTests: XCTestCase {
    func testSnapshotIsEvaluatedFromExplicitHealthObservation() {
        let snapshot = EvaluateRuntimeHealthUseCase().snapshot(observation: observation())

        XCTAssertEqual(snapshot.vmState, .running)
        XCTAssertEqual(snapshot.failureReasons, [])
        XCTAssertEqual(snapshot.vmIP, "192.168.64.2")
        XCTAssertEqual(snapshot.proxyPort, 80)
    }

    func testObservationMapsSkippedProxyHTTPReadsFromMissingProxyPortInUseCase() {
        let observation = EvaluateRuntimeHealthUseCase().observation(from: healthReads(
            guestRuntimeState: RuntimeGuestRuntimeStateObservation(
                loadedState: nil,
                freshState: nil,
                isFresh: false
            ),
            proxyPortReadState: .missing("proxy port not configured"),
            hostProxyHTTP: nil,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            auditProxyStatus: nil
        ))

        XCTAssertNil(observation.proxyPort)
        XCTAssertEqual(observation.hostProxyHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(observation.redisUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(observation.swaggerUIHTTP, RuntimeHTTPStatusText.missingProxyPort)
        XCTAssertEqual(
            observation.containerObservation.observedValue?.auditProxyHTTP,
            RuntimeHTTPStatusText.missingProxyPort
        )
        XCTAssertEqual(
            observation.containerObservation.observedValue?.auditProxyStatusReadError,
            RuntimeHTTPStatusText.missingProxyPort
        )
        XCTAssertEqual(
            observation.containerObservation.observedValue?.auditProxyStatusReadState,
            .skippedMissingProxyPort
        )
    }

    func testBootstrapResultFromDifferentBootDoesNotCreateVMFailure() {
        let snapshot = EvaluateRuntimeHealthUseCase().snapshot(observation: observation(
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            loadedGuestRuntimeState: GuestRuntimeStateDocument(
                vmIP: "192.168.64.2",
                updatedAt: "2026-05-21T12:35:00Z",
                bootID: "current-boot",
                guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
                redisUIHTTP: "200",
                swaggerUIHTTP: "200"
            ),
            guestBootstrapResult: .loaded(bootstrapResult(
                status: .failed,
                bootID: "old-boot",
                reasonCodes: [.guestBootstrapMissingRuntimePackages]
            ))
        ))

        XCTAssertFalse(snapshot.failureReasons.contains(RuntimeFailureReason.guestBootstrapMissingRuntimePackages))
        XCTAssertTrue(snapshot.failureReasons.contains(RuntimeFailureReason.guestHTTP(RuntimeHTTPStatusText.bootstrapPending)))
    }

    func testFreshBootstrapFailureIsEvaluatedByUseCaseNotAdapter() {
        let snapshot = EvaluateRuntimeHealthUseCase().snapshot(observation: observation(
            guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
            loadedGuestRuntimeState: GuestRuntimeStateDocument(
                vmIP: "192.168.64.2",
                updatedAt: "2026-05-21T12:35:00Z",
                bootID: "current-boot",
                guestHTTP: RuntimeHTTPStatusText.bootstrapPending,
                redisUIHTTP: "200",
                swaggerUIHTTP: "200"
            ),
            guestBootstrapResult: .loaded(bootstrapResult(
                status: .failed,
                bootID: "current-boot",
                reasonCodes: [.guestBootstrapMissingRuntimePackages]
            ))
        ))

        XCTAssertTrue(snapshot.failureReasons.contains(RuntimeFailureReason.guestBootstrapMissingRuntimePackages))
        XCTAssertTrue(snapshot.vmErrors.contains(RuntimeVMError.guestBootstrapMissingRuntimePackages))
    }

    func testComposeServicesReadResultLoadsFreshReportedServices() {
        let services = [
            RuntimeContainerServiceObservation(service: "app", state: "running", health: "healthy"),
        ]

        let result = EvaluateRuntimeHealthUseCase().composeServicesReadResult(
            freshState: guestState(containerServices: services),
            loadedState: nil,
            readFailureReasons: []
        )

        XCTAssertEqual(result.state, .loaded)
        XCTAssertEqual(result.services, services)
        XCTAssertNil(result.readError)
    }

    func testComposeServicesReadResultKeepsFreshMissingServicesDistinct() {
        let result = EvaluateRuntimeHealthUseCase().composeServicesReadResult(
            freshState: guestState(containerServices: nil),
            loadedState: nil,
            readFailureReasons: []
        )

        XCTAssertEqual(result.state, .missing)
        XCTAssertEqual(result.services, [])
        XCTAssertEqual(result.readError, "container-services-missing")
    }

    func testComposeServicesReadResultKeepsInvalidStaleAndMissingRuntimeStateDistinct() {
        let useCase = EvaluateRuntimeHealthUseCase()

        XCTAssertEqual(
            useCase.composeServicesReadResult(
                freshState: nil,
                loadedState: nil,
                readFailureReasons: [.guestRuntimeStateInvalid]
            ),
            RuntimeComposeServicesReadResult(
                state: .invalid,
                services: [],
                readError: "guest-runtime-state-invalid"
            )
        )
        XCTAssertEqual(
            useCase.composeServicesReadResult(
                freshState: nil,
                loadedState: guestState(containerServices: []),
                readFailureReasons: []
            ),
            RuntimeComposeServicesReadResult(
                state: .stale,
                services: [],
                readError: "guest-runtime-state-stale"
            )
        )
        XCTAssertEqual(
            useCase.composeServicesReadResult(
                freshState: nil,
                loadedState: nil,
                readFailureReasons: []
            ),
            RuntimeComposeServicesReadResult(
                state: .missing,
                services: [],
                readError: "guest-runtime-state-missing"
            )
        )
    }

    func testObservationMapsGuestRuntimeReadIssueToInvalidFailureReasonInUseCase() {
        let useCase = EvaluateRuntimeHealthUseCase()
        let observation = useCase.observation(from: healthReads(
            guestRuntimeState: RuntimeGuestRuntimeStateObservation(
                loadedState: nil,
                freshState: nil,
                isFresh: false,
                readIssue: .loadFailed("runtime-state unreadable")
            )
        ))

        XCTAssertEqual(observation.guestRuntimeState, RuntimeGuestRuntimeStateInput.invalid)
        XCTAssertTrue(observation.configurationFailureReasons.contains(RuntimeFailureReason.guestRuntimeStateInvalid))
        XCTAssertEqual(observation.containerObservation.observedValue?.composeServicesReadState, .invalid)
        XCTAssertEqual(observation.containerObservation.observedValue?.composeServicesReadError, "guest-runtime-state-invalid")
    }
}

private func guestState(
    containerServices: [RuntimeContainerServiceObservation]?
) -> GuestRuntimeStateDocument {
    GuestRuntimeStateDocument(
        vmIP: "192.168.64.2",
        updatedAt: "2026-05-21T12:35:00Z",
        bootID: "current-boot",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        containerServices: containerServices
    )
}

private func observation(
    guestHTTP: String = "200",
    loadedGuestRuntimeState: GuestRuntimeStateDocument? = GuestRuntimeStateDocument(
        vmIP: "192.168.64.2",
        updatedAt: "2026-05-21T12:35:00Z",
        bootID: "current-boot",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200"
    ),
    guestBootstrapResult: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> = .missing
) -> RuntimeHealthObservation {
    RuntimeHealthObservation(
        vmExecutable: .executable,
        proxyExecutable: .executable,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmLifecycle: nil,
        guestRuntimeState: .fresh(
            vmIP: "192.168.64.2",
            guestHTTP: guestHTTPInput(guestHTTP)
        ),
        loadedGuestRuntimeState: loadedGuestRuntimeState,
        proxyPort: 80,
        proxyPortReadState: .loaded(80),
        hostProxyHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        containerObservation: .notReported,
        vitalDBObservation: .notReported,
        reportedVMErrors: [],
        configurationFailureReasons: [],
        proxyPortFailureReasons: [],
        guestBootstrapResult: guestBootstrapResult,
        observedAt: date("2026-05-21T12:35:00Z"),
        guestBootstrapFreshnessGraceSeconds: 60
    )
}

private func healthReads(
    guestRuntimeState: RuntimeGuestRuntimeStateObservation,
    proxyPortReadState: RuntimeProxyPortReadState = .loaded(80),
    hostProxyHTTP: String? = "200",
    redisUIHTTP: String? = "200",
    swaggerUIHTTP: String? = "200",
    auditProxyStatus: RuntimeAuditProxyStatusReadResult? = nil
) -> RuntimeHealthObservationReads {
    RuntimeHealthObservationReads(
        vmExecutable: .executable,
        proxyExecutable: .executable,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmLifecycleLoadResult: .missing,
        guestRuntimeState: guestRuntimeState,
        proxyPortReadState: proxyPortReadState,
        hostProxyHTTP: hostProxyHTTP.map(RuntimeHTTPProbeResult.reportedStatus),
        redisUIHTTP: redisUIHTTP.map(RuntimeHTTPProbeResult.reportedStatus),
        swaggerUIHTTP: swaggerUIHTTP.map(RuntimeHTTPProbeResult.reportedStatus),
        auditProxyStatus: auditProxyStatus,
        runtimeStateFileModifiedAt: RuntimeFileModifiedAtReadResult(updatedAt: nil, readError: nil),
        containerLogsMetadata: RuntimeContainerLogsMetadata(present: false, bytes: nil, updatedAt: nil, error: nil),
        proxyListenerObservation: nil,
        guestBootstrapResult: .missing,
        observedAt: date("2026-05-21T12:35:00Z"),
        guestBootstrapFreshnessGraceSeconds: 60
    )
}

private func bootstrapResult(
    status: GuestBootstrapStatus,
    bootID: String?,
    reasonCodes: [RuntimeFailureReason]?
) -> GuestBootstrapResultDocument {
    GuestBootstrapResultDocument(
        schemaVersion: 2,
        bootID: bootID,
        operation: .unknown("bootstrap"),
        status: status,
        message: nil,
        reasonCodes: reasonCodes,
        updatedAt: "2026-05-21T12:34:57Z"
    )
}

private func guestHTTPInput(_ value: String) -> RuntimeGuestHTTPStatusInput {
    if Int(value) != nil
        || value == RuntimeHTTPStatusText.bootstrapPending
        || value == RuntimeHTTPStatusText.missingVMIP {
        return .reportedStatus(value)
    }
    return .probeFailed(value)
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

import Contracts
import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeStatusDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeStatusDisplayPolicy()

    func testHealthDetailsOwnServiceUptimeMappingAndFormatting() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            sleepPreventionServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200",
            redisUIHTTP: "503"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "app", uptimeSeconds: 3_661),
                RuntimeContainerServiceObservation(service: "edge", uptimeSeconds: 60),
                RuntimeContainerServiceObservation(service: "redis", state: "running", health: "healthy", uptimeSeconds: 5),
            ]
        )

        let items = policy.healthDetails(status: status, observation: observation)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "01:01:01")
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.value.uptimeText, "00:01:00")
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.text, AppConstants.StatusText.healthy)
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.severity, .healthy)
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.uptimeText, "00:00:05")
    }

    func testOverallHealthDoesNotDisplayUptime() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            vmIP: "192.168.64.10",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "app", uptimeSeconds: 3_661),
            ]
        )

        let value = policy.overallHealth(status: status, observation: observation)

        XCTAssertEqual(value.text, AppConstants.StatusText.healthy)
        XCTAssertNil(value.uptimeText)
    }

    func testUpdateOperationTakesPriorityOverTransientProxyFailures() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: false,
            watchdogServiceLoaded: true,
            runtimeState: .updating,
            operation: .applyBundle,
            guestHTTP: "000failed",
            hostProxyHTTP: nil
        )

        let overall = policy.overallHealth(status: status, observation: nil)
        let vitalServer = policy.vitalServerAvailability(status: status, observation: nil)

        XCTAssertEqual(overall.text, AppConstants.StatusText.updating)
        XCTAssertEqual(overall.severity, .warning)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.updating)
        XCTAssertEqual(vitalServer.severity, .warning)
    }

    func testOverallHealthDoesNotInferStartingWhenRuntimeStateIsMissing() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmIP: "192.168.64.10",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        let value = policy.overallHealth(status: status, observation: nil)

        XCTAssertEqual(value.text, AppConstants.StatusText.unknown)
        XCTAssertEqual(value.severity, .neutral)
    }

    func testRemoteConsoleAvailabilityShowsReachabilityAndUptime() {
        let now = ISO8601DateFormatter().date(from: "2026-05-29T00:02:05Z")!
        let status = RuntimeStatus(
            runtimeControlHTTP: "200",
            runtimeControlStartedAt: "2026-05-29T00:01:00Z"
        )

        let value = policy.remoteConsoleAvailability(status: status, now: now)

        XCTAssertEqual(value.text, AppConstants.StatusText.reachable)
        XCTAssertEqual(value.severity, .healthy)
        XCTAssertEqual(value.uptimeText, "00:01:05")
    }

    func testActionNeededIsHiddenWhenRuntimeIsReady() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            vmIP: "192.168.64.10",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        XCTAssertNil(policy.actionNeeded(status: status))
    }

    func testActionNeededUsesSimpleUserFacingRuntimeRepairAction() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .degraded,
            guestHTTP: "failed",
            hostProxyHTTP: "failed",
            failureReasons: [.guestRuntimeStateStale]
        )

        let item = policy.actionNeeded(status: status)

        XCTAssertEqual(item?.title, AppConstants.StatusText.vitalServerUnavailable)
        XCTAssertEqual(item?.recommendedAction, "Restart guest agent")
        XCTAssertEqual(item?.severity, .warning)
    }

    func testActionNeededPrefersProxyRepairForProxyPortConflict() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .degraded,
            guestHTTP: "200",
            hostProxyHTTP: "failed",
            failureReasons: [.proxyPortInUse(port: 80, listeners: "nginx-1234")]
        )

        let item = policy.actionNeeded(status: status)

        XCTAssertEqual(item?.title, AppConstants.StatusText.vitalServerUnavailable)
        XCTAssertEqual(item?.recommendedAction, "Free host proxy port")
        XCTAssertEqual(item?.severity, .critical)
    }

    func testActionNeededDoesNotInferRepairWithoutExplicitFailureReason() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            watchdogServiceLoaded: true,
            runtimeState: .degraded,
            guestHTTP: "failed",
            hostProxyHTTP: "failed"
        )

        XCTAssertNil(policy.actionNeeded(status: status))
    }

    func testActionNeededDoesNotInferRepairFromStatusReadIssue() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            watchdogServiceLoaded: true,
            runtimeState: .degraded,
            readIssues: [
                RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout"),
            ]
        )

        let action = policy.actionNeeded(status: status)
        let details = policy.healthDetails(status: status, observation: nil)

        XCTAssertEqual(action?.recommendedAction, AppConstants.Actions.openLogs)
        XCTAssertEqual(item(AppConstants.Labels.statusReadIssues, in: details)?.value.text, "hostProxyHTTP: exitCode=28 stderr=timeout")
    }

    func testStatusDisplayTextIsStandardizedAcrossSummaryAndDetails() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            vmState: .running,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "redis", state: "running", health: "healthy"),
            ]
        )

        let summary = policy.vitalServerAvailability(status: status, observation: observation)
        let details = policy.healthDetails(status: status, observation: observation)

        XCTAssertEqual(summary.text, AppConstants.StatusText.reachable)
        XCTAssertEqual(item(AppConstants.Labels.runtimeInstallation, in: details)?.value.text, AppConstants.StatusText.installed)
        XCTAssertEqual(item(AppConstants.Labels.vmState, in: details)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.vmState, in: details)?.value.severity, .healthy)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.text, AppConstants.StatusText.reachable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: details)?.value.text, AppConstants.StatusText.reachable)
        XCTAssertEqual(item(GeneratedRelease.redisName, in: details)?.value.text, AppConstants.StatusText.healthy)
    }

    func testUptimeUsesDockerStartedAtWithNanosecondFraction() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(
                    service: "app",
                    startedAt: "2026-05-26T04:35:35.123456789Z",
                    uptimeSeconds: 1
                ),
            ]
        )
        let now = ISO8601DateFormatter().date(from: "2026-05-26T04:35:40Z")!

        let items = policy.healthDetails(status: status, observation: observation, now: now)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "00:00:04")
    }

    func testUptimeFallsBackToObservedAtWhenStartedAtIsMissing() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            runtimeStateUpdatedAt: "2026-05-26T04:35:35Z",
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "app", uptimeSeconds: 10),
            ]
        )
        let now = ISO8601DateFormatter().date(from: "2026-05-26T04:35:40Z")!

        let items = policy.healthDetails(status: status, observation: observation, now: now)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "00:00:15")
    }

    func testUptimeDisplaysDaysBeforeClockDuration() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "app", uptimeSeconds: 183_845),
            ]
        )

        let items = policy.healthDetails(status: status, observation: observation)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "2d 03:04:05")
    }

    func testAdvancedServiceHealthOwnsLabelsActionsAndHTTPStatusDisplay() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            sleepPreventionServiceLoaded: true,
            watchdogServiceLoaded: true,
            guestHTTP: "200",
            hostProxyHTTP: "503",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "app", uptimeSeconds: 1),
                RuntimeContainerServiceObservation(service: "edge", uptimeSeconds: 2),
                RuntimeContainerServiceObservation(service: "redis-ui", uptimeSeconds: 3),
                RuntimeContainerServiceObservation(service: "swagger-ui", uptimeSeconds: 4),
            ]
        )

        let items = policy.advancedServiceHealth(status: status, observation: observation)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.action, .openVitalServer)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "00:00:01")
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.httpStatus, "503")
        XCTAssertEqual(item(AppConstants.Labels.guestLogSyncService, in: items)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.sleepPreventionService, in: items)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: items)?.action, .openRedisUI)
        XCTAssertEqual(item(GeneratedRelease.swaggerUIName, in: items)?.action, .openSwagger)
    }

    func testAdvancedServiceHealthUsesTypedServiceStateBeforeLegacyLoadedBool() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            guestLogSyncServiceLoaded: false,
            watchdogServiceLoaded: false,
            vmServiceState: .permissionDenied("launchctl denied"),
            proxyServiceState: .notLoaded,
            guestLogSyncServiceState: .readFailed("launchctl failed"),
            watchdogServiceState: .loaded
        )

        let items = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: items)?.value.text, "Permission denied")
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: items)?.value.text, AppConstants.StatusText.stopped)
        XCTAssertEqual(item(AppConstants.Labels.guestLogSyncService, in: items)?.value.text, "Read failed")
        XCTAssertEqual(item(AppConstants.Labels.watchdogService, in: items)?.value.text, AppConstants.StatusText.running)
    }

    func testServiceAndReachabilityFallbacksUseReducedStatusVocabulary() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            guestLogSyncServiceLoaded: false,
            watchdogServiceLoaded: false,
            guestHTTP: "failed",
            hostProxyHTTP: nil
        )

        let healthDetails = policy.healthDetails(status: status, observation: nil)
        let serviceHealth = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.watchdog, in: healthDetails)?.value.text, AppConstants.StatusText.stopped)
        XCTAssertEqual(item(AppConstants.Labels.vmService, in: serviceHealth)?.value.text, AppConstants.StatusText.stopped)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.unreachable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.notReported)
    }

    func testVMStateDisplayMapsRuntimeStatesToOperatorSeverity() {
        XCTAssertEqual(policy.vmStateValue(.running).text, AppConstants.StatusText.running)
        XCTAssertEqual(policy.vmStateValue(.running).severity, .healthy)
        XCTAssertEqual(policy.vmStateValue(.starting).severity, .warning)
        XCTAssertEqual(policy.vmStateValue(.stale).severity, .warning)
        XCTAssertEqual(policy.vmStateValue(.unreachable).severity, .critical)
        XCTAssertEqual(policy.vmStateValue(nil).text, AppConstants.StatusText.unknown)
    }

    func testHealthDetailsDisplayVMErrorsWhenPresent() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmState: .stale,
            vmErrors: [.runtimeStateStale, .diskAttachmentInvalid, .guestDiskIO, .guestHTTP("failed")]
        )

        let items = policy.healthDetails(status: status, observation: nil)

        XCTAssertEqual(
            item(AppConstants.Labels.vmErrors, in: items)?.value.text,
            "Guest runtime state stale, VM disk attachment invalid, Guest disk I/O error, Guest HTTP failed"
        )
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: items)?.value.severity, .critical)
    }

    func testHealthDetailsDisplayDomainFailureReasonsWhenPresent() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            failureReasons: [.hostProxyHTTP("503"), .guestRuntimeStateStale]
        )

        let items = policy.healthDetails(status: status, observation: nil)

        XCTAssertEqual(
            item(AppConstants.Labels.failureReasons, in: items)?.value.text,
            "Host proxy HTTP 503 (Restart host proxy service), Guest runtime state stale (Restart guest agent)"
        )
        XCTAssertEqual(item(AppConstants.Labels.failureReasons, in: items)?.value.severity, .critical)
    }

    func testRecorderSummaryOwnsRecorderDisplayText() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: RuntimeAuditProxyStatusDocument(
                activeRecorderConnections: 2,
                recorders: [
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_OLD",
                        activeConnections: 1,
                        selectedIp: nil,
                        lastSeenAt: "2026-05-24T00:00:00Z"
                    ),
                    RuntimeRecorderConnectionObservation(
                        vrcode: "VR_NEW",
                        activeConnections: 1,
                        selectedIp: "192.168.64.10",
                        lastSeenAt: "2026-05-24T01:00:00Z"
                    ),
                ]
            ),
            containerLogsPresent: true,
            containerLogsBytes: 1
        )

        let status = RuntimeStatus(vitalDBObservation: VitalDBObservationDocument(
            observedAt: "2026-05-24T02:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_OBSERVED",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-24T02:00:00Z",
                    online: true
                ),
                VitalDBRecorderObservation(
                    vrcode: "VR_OBSERVED",
                    ip: "192.168.64.19",
                    lastSeenAt: "2026-05-24T01:59:00Z",
                    online: true
                ),
                VitalDBRecorderObservation(
                    vrcode: "VR_STALE",
                    ip: "192.168.64.21",
                    lastSeenAt: "2026-05-24T00:00:00Z",
                    online: false,
                    stale: true
                ),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-1", online: true),
            ],
            anomalies: [
                VitalDBAnomalyObservation(
                    id: "stale-recorder:VR_STALE",
                    kind: .staleRecorder,
                    severity: .warning,
                    observedAt: "2026-05-24T02:00:00Z",
                    subject: "VR_STALE",
                    message: "recorder is stale"
                ),
            ]
        ))

        let summary = policy.recorderSummary(status: status, observation: observation)

        XCTAssertEqual(summary.activeConnections, "2")
        XCTAssertEqual(summary.knownRecorders, "2")
        XCTAssertEqual(summary.onlineRecorders, "1")
        XCTAssertEqual(summary.staleRecorders, "1")
        XCTAssertEqual(summary.knownBeds, "1")
        XCTAssertEqual(summary.anomalies, "1")
        XCTAssertEqual(summary.latestRecorder, "VR_OBSERVED 192.168.64.20")
        XCTAssertEqual(summary.observedAt, "2026-05-24T02:00:00Z")
    }

    func testRecorderSummaryDisplaysMissingLatestRecorderIPAsNotReported() {
        let status = RuntimeStatus(vitalDBObservation: VitalDBObservationDocument(
            observedAt: "2026-05-24T02:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_NO_IP",
                    ip: nil,
                    lastSeenAt: "2026-05-24T02:00:00Z",
                    online: true
                ),
            ]
        ))

        let summary = policy.recorderSummary(status: status, observation: nil)

        XCTAssertEqual(summary.latestRecorder, "VR_NO_IP \(AppConstants.StatusText.notReported)")
    }

    func testVitalServerUptimeDoesNotFallBackToStatusStartedAt() {
        let now = ISO8601DateFormatter().date(from: "2026-05-29T00:02:05Z")!
        let status = RuntimeStatus(
            runtimeInstalled: true,
            startedAt: "2026-05-29T00:01:00Z",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        let value = policy.vitalServerAvailability(status: status, observation: nil, now: now)

        XCTAssertNil(value.uptimeText)
    }

    func testComposeServiceMissingAndRunningWithoutHealthAreNotHealthyFallbacks() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: nil,
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(service: "redis", state: "running", health: nil),
            ]
        )

        let items = policy.healthDetails(status: status, observation: observation)

        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.severity, .warning)
        XCTAssertEqual(item(AppConstants.Labels.vitalDBObserver, in: items)?.value.text, AppConstants.StatusText.notReported)
        XCTAssertEqual(item(AppConstants.Labels.vitalDBObserver, in: items)?.value.severity, .neutral)
    }

    func testRecorderSummaryDoesNotDisplayUnavailableObservationMetricsAsZero() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: RuntimeAuditProxyStatusDocument(activeRecorderConnections: 2),
            containerLogsPresent: true,
            containerLogsBytes: 1
        )

        let summary = policy.recorderSummary(status: RuntimeStatus(), observation: observation)

        XCTAssertEqual(summary.activeConnections, "2")
        XCTAssertEqual(summary.knownRecorders, AppConstants.StatusText.notReported)
        XCTAssertEqual(summary.onlineRecorders, AppConstants.StatusText.notReported)
        XCTAssertEqual(summary.staleRecorders, AppConstants.StatusText.notReported)
        XCTAssertEqual(summary.knownBeds, AppConstants.StatusText.notReported)
        XCTAssertEqual(summary.anomalies, AppConstants.StatusText.notReported)
        XCTAssertNil(summary.latestRecorder)
        XCTAssertNil(summary.observedAt)
    }

    private func item(
        _ label: String,
        in items: [RuntimeStatusDisplayPolicy.HealthItem]
    ) -> RuntimeStatusDisplayPolicy.HealthItem? {
        items.first { $0.label == label }
    }

    private func item(
        _ label: String,
        in items: [RuntimeStatusDisplayPolicy.ServiceHealthItem]
    ) -> RuntimeStatusDisplayPolicy.ServiceHealthItem? {
        items.first { $0.label == label }
    }
}

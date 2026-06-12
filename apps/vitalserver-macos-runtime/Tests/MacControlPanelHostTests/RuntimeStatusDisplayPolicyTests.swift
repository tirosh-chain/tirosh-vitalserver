import Contracts
import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeStatusDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeStatusDisplayPolicy()

    func testStatusPollingIntervalUsesFastRefreshDuringInstall() {
        let pollingPolicy = RuntimeStatusPollingIntervalPolicy()
        let status = RuntimeStatus(
            runtimeState: .installing,
            operation: .install,
            progress: RuntimeProgressDocument(
                operation: .install,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "installing",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-08T00:00:00Z"
            )
        )

        XCTAssertEqual(
            pollingPolicy.statusPollingIntervalNanoseconds(status: status),
            RuntimeStatusPollingIntervalPolicy.activeOperationInterval
        )
    }

    func testStatusPollingIntervalUsesSteadyRefreshOutsideActiveOperation() {
        let pollingPolicy = RuntimeStatusPollingIntervalPolicy()
        let status = RuntimeStatus(runtimeState: .healthy, operation: .watchdog)

        XCTAssertEqual(
            pollingPolicy.statusPollingIntervalNanoseconds(status: status),
            RuntimeStatusPollingIntervalPolicy.steadyStateInterval
        )
    }

    func testServiceStatePresentationPolicyOwnsServiceStateSeverity() {
        let serviceStatePolicy = RuntimeStatusServiceStatePresentationPolicy()

        XCTAssertEqual(serviceStatePolicy.serviceStateSeverity(.loaded), .healthy)
        XCTAssertEqual(serviceStatePolicy.serviceStateSeverity(.notLoaded), .warning)
        XCTAssertEqual(serviceStatePolicy.serviceStateSeverity(.readFailed("denied")), .warning)
        XCTAssertEqual(serviceStatePolicy.serviceStateSeverity(.permissionDenied("denied")), .warning)
        XCTAssertEqual(serviceStatePolicy.serviceStateSeverity(.unknown("mystery")), .neutral)
        XCTAssertTrue(serviceStatePolicy.shouldDisplayOperationStateInsteadOfServiceState(.loaded))
        XCTAssertFalse(serviceStatePolicy.shouldDisplayOperationStateInsteadOfServiceState(.readFailed("denied")))
    }

    func testVMStatePresentationPolicyOwnsVMStateSeverity() {
        let vmStatePolicy = RuntimeStatusVMStatePresentationPolicy()

        XCTAssertEqual(vmStatePolicy.vmStateSeverity(.running), .healthy)
        XCTAssertEqual(vmStatePolicy.vmStateSeverity(.starting), .warning)
        XCTAssertEqual(vmStatePolicy.vmStateSeverity(.stale), .warning)
        XCTAssertEqual(vmStatePolicy.vmStateSeverity(.failed), .critical)
        XCTAssertEqual(vmStatePolicy.vmStateSeverity(.notInstalled), .critical)
        XCTAssertEqual(vmStatePolicy.vmStateSeverity(.unknown("mystery")), .neutral)
        XCTAssertEqual(vmStatePolicy.vmStateSeverity(nil), .neutral)
    }

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
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
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

    func testInstallOperationTakesPriorityOverInitialDegradedAvailability() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            watchdogServiceLoaded: true,
            runtimeState: .installing,
            operation: .status,
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            progress: RuntimeProgressDocument(
                operation: .install,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "installing",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-08T00:00:00Z"
            )
        )

        let overall = policy.overallHealth(status: status, observation: nil)
        let vitalServer = policy.vitalServerAvailability(status: status, observation: nil)

        XCTAssertEqual(overall.text, AppConstants.StatusText.installing)
        XCTAssertEqual(overall.severity, .warning)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.installing)
        XCTAssertEqual(vitalServer.severity, .warning)
    }

    func testAdvancedServiceHealthShowsUpdatingForTransientServiceChangesDuringUpdate() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            guestLogSyncServiceLoaded: false,
            sleepPreventionServiceLoaded: false,
            watchdogServiceLoaded: true,
            vmServiceState: .notLoaded,
            proxyServiceState: .notLoaded,
            guestLogSyncServiceState: .notLoaded,
            sleepPreventionServiceState: .notLoaded,
            watchdogServiceState: .loaded,
            runtimeState: .updating,
            operation: .applyBundle,
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            redisUIHTTP: "503",
            swaggerUIHTTP: nil
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "000",
            auditProxyStatus: nil,
            containerLogsPresent: false,
            containerLogsBytes: 0,
            composeServices: []
        )

        let vmHealth = policy.advancedVMHealth(status: status)
        let serviceHealth = policy.advancedServiceHealth(status: status, observation: observation)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.stopped)
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceHealth))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(AppConstants.Labels.watchdogService, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(AppConstants.Labels.vitalDBObserver, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
    }

    func testAdvancedServiceHealthShowsInstallingForInitialServiceChangesDuringInstall() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            guestLogSyncServiceLoaded: false,
            sleepPreventionServiceLoaded: false,
            watchdogServiceLoaded: true,
            vmServiceState: .notLoaded,
            proxyServiceState: .notLoaded,
            guestLogSyncServiceState: .notLoaded,
            sleepPreventionServiceState: .notLoaded,
            watchdogServiceState: .loaded,
            runtimeState: .installing,
            operation: .status,
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            redisUIHTTP: "503",
            swaggerUIHTTP: nil,
            progress: RuntimeProgressDocument(
                operation: .install,
                phase: .running,
                step: nil,
                stepStatus: nil,
                message: "installing",
                reasonCodes: [],
                startedAt: nil,
                updatedAt: "2026-06-08T00:00:00Z"
            )
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "000",
            auditProxyStatus: nil,
            containerLogsPresent: false,
            containerLogsBytes: 0,
            composeServices: []
        )

        let vmHealth = policy.advancedVMHealth(status: status)
        let serviceHealth = policy.advancedServiceHealth(status: status, observation: observation)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceHealth))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(AppConstants.Labels.watchdogService, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(AppConstants.Labels.vitalDBObserver, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
    }

    func testAdvancedServiceHealthShowsInitializingWhileRuntimeBecomesReady() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            guestLogSyncServiceLoaded: false,
            sleepPreventionServiceLoaded: false,
            watchdogServiceLoaded: true,
            vmServiceState: .notLoaded,
            proxyServiceState: .notLoaded,
            guestLogSyncServiceState: .notLoaded,
            sleepPreventionServiceState: .notLoaded,
            watchdogServiceState: .loaded,
            runtimeState: .initializing,
            operation: .install,
            installStateDocument: RuntimeInstallStateDocument(
                state: .provisioned,
                mode: .provision,
                updatedAt: "2026-06-09T14:06:25Z",
                message: "runtime install provisioned"
            ),
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            redisUIHTTP: "503",
            swaggerUIHTTP: nil
        )
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "000",
            auditProxyStatus: nil,
            containerLogsPresent: false,
            containerLogsBytes: 0,
            composeServices: []
        )

        let overall = policy.overallHealth(status: status, observation: observation)
        let vitalServer = policy.vitalServerAvailability(status: status, observation: observation)
        let vmHealth = policy.advancedVMHealth(status: status)
        let serviceHealth = policy.advancedServiceHealth(status: status, observation: observation)

        XCTAssertEqual(overall.text, AppConstants.StatusText.initializing)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.initializing)
        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.initializing)
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.initializing)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.initializing)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.initializing)
    }

    func testAdvancedServiceHealthPreservesServiceStateReadFailuresDuringUpdate() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceState: .permissionDenied("launchctl denied"),
            proxyServiceState: .readFailed("launchctl failed"),
            guestLogSyncServiceState: .unknown("paused"),
            runtimeState: .updating,
            operation: .applyBundle
        )

        let vmHealth = policy.advancedVMHealth(status: status)
        let serviceHealth = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, "Permission denied")
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceHealth))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, "Read failed")
        XCTAssertEqual(item(AppConstants.Labels.guestLogSyncService, in: serviceHealth)?.value.text, "Paused")
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

    func testHealthDetailsDisplaysExplicitRuntimeInstallationState() {
        let status = RuntimeStatus(
            runtimeInstalled: false,
            runtimeInstallationState: .present,
            vmServiceState: .notLoaded
        )

        let details = policy.healthDetails(status: status, observation: nil)
        let installation = item(AppConstants.Labels.runtimeInstallation, in: details)?.value

        XCTAssertEqual(installation?.text, "Present but not executable")
        XCTAssertEqual(installation?.severity, .critical)
    }

    func testSummaryPoliciesUseExplicitRuntimeInstallationStateBeforeLegacyInstalledBool() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .present,
            hostProxyHTTP: "200"
        )

        let overall = policy.overallHealth(status: status, observation: nil)
        let vitalServer = policy.vitalServerAvailability(status: status, observation: nil)
        let actionNeeded = policy.actionNeeded(status: status)

        XCTAssertEqual(overall.text, "Present but not executable")
        XCTAssertEqual(overall.severity, .critical)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(vitalServer.severity, .critical)
        XCTAssertEqual(actionNeeded?.title, "Present but not executable")
        XCTAssertEqual(actionNeeded?.recommendedAction, AppConstants.Actions.openLogs)
        XCTAssertEqual(actionNeeded?.severity, .critical)
    }

    func testUptimePrefersExplicitSecondsOverDockerStartedAt() {
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

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText, "00:00:01")
    }

    func testUptimeUsesDockerStartedAtWithNanosecondFractionWhenExplicitSecondsAreMissing() {
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
                    startedAt: "2026-05-26T04:35:35.123456789Z"
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
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            guestLogSyncServiceState: .loaded,
            sleepPreventionServiceState: .loaded,
            watchdogServiceState: .loaded,
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

        let vmItems = policy.advancedVMHealth(status: status)
        let serviceItems = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmItems)?.value.text, "Permission denied")
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceItems))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceItems)?.value.text, AppConstants.StatusText.stopped)
        XCTAssertEqual(item(AppConstants.Labels.guestLogSyncService, in: serviceItems)?.value.text, "Read failed")
        XCTAssertEqual(item(AppConstants.Labels.watchdogService, in: serviceItems)?.value.text, AppConstants.StatusText.running)
    }

    func testServiceDisplayDoesNotInferLaunchdStateFromLegacyLoadedBools() {
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
        let vmHealth = policy.advancedVMHealth(status: status)
        let serviceHealth = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.watchdog, in: healthDetails)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.unreachable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.notReported)
    }

    func testAdvancedVMHealthSeparatesVMIntegrityFromServiceLiveness() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            sleepPreventionServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            guestLogSyncServiceState: .loaded,
            sleepPreventionServiceState: .loaded,
            watchdogServiceState: .loaded,
            vmState: .failed,
            vmErrors: [.guestFilesystemError],
            vmIP: "192.168.64.8",
            guestHTTP: "200",
            hostProxyHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )

        let vmItems = policy.advancedVMHealth(status: status)
        let serviceItems = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.vmState, in: vmItems)?.value.text, AppConstants.StatusText.failed)
        XCTAssertEqual(item(AppConstants.Labels.vmState, in: vmItems)?.value.severity, .critical)
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: vmItems)?.value.text, "Guest filesystem error")
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: vmItems)?.value.severity, .critical)
        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmItems)?.value.text, AppConstants.StatusText.running)
        XCTAssertNil(item(AppConstants.Labels.vmState, in: serviceItems))
        XCTAssertNil(item(AppConstants.Labels.vmErrors, in: serviceItems))
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceItems))
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.value.text, AppConstants.StatusText.reachable)
    }

    func testInitialGuestStateStaleDisplaysAsWaitingDuringVMStart() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            sleepPreventionServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            guestLogSyncServiceState: .loaded,
            sleepPreventionServiceState: .loaded,
            watchdogServiceState: .loaded,
            vmState: .starting,
            vmErrors: [.runtimeStateStale],
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            hostProxyHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: [.guestRuntimeStateStale]
        )

        let details = policy.healthDetails(status: status, observation: nil)
        let vmItems = policy.advancedVMHealth(status: status)
        let serviceItems = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.vmIPAddress, in: details)?.value.text, AppConstants.StatusText.guestStateStale)
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: details)?.value.text, "Guest runtime state stale")
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: details)?.value.severity, .warning)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.text, AppConstants.StatusText.guestStateStale)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.severity, .warning)
        XCTAssertEqual(item(AppConstants.Labels.vmIPAddress, in: vmItems)?.value.text, AppConstants.StatusText.guestStateStale)
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: vmItems)?.value.text, "Guest runtime state stale")
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: vmItems)?.value.severity, .warning)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.value.text, AppConstants.StatusText.guestStateStale)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.value.severity, .warning)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.httpStatus, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceItems)?.value.text, AppConstants.StatusText.reachable)
    }

    func testGuestStateStaleAfterVMRunningRemainsFailurePresentation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            vmState: .running,
            vmErrors: [.runtimeStateStale],
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            hostProxyHTTP: "200",
            failureReasons: [.guestRuntimeStateStale]
        )

        let details = policy.healthDetails(status: status, observation: nil)
        let vmItems = policy.advancedVMHealth(status: status)
        let serviceItems = policy.advancedServiceHealth(status: status, observation: nil)

        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: details)?.value.severity, .critical)
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: vmItems)?.value.severity, .critical)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.value.text, AppConstants.StatusText.failed)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.httpStatus, RuntimeHTTPStatusText.missingVMIP)
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

        let vitalDBObservation = VitalDBObservationDocument(
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
        )

        let summary = policy.recorderSummary(
            observation: observation,
            vitalDBObservation: vitalDBObservation
        )

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
        let vitalDBObservation = VitalDBObservationDocument(
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
        )

        let summary = policy.recorderSummary(
            observation: nil,
            vitalDBObservation: vitalDBObservation
        )

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

    func testComposeServicesReadFailureIsDisplayedInsteadOfMissingServiceFallback() {
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
            composeServicesReadState: .invalid,
            composeServices: [],
            composeServicesReadError: "guest-runtime-state-invalid"
        )

        let items = policy.healthDetails(status: status, observation: observation)

        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.text, "guest-runtime-state-invalid")
        XCTAssertEqual(item(GeneratedRelease.redisName, in: items)?.value.severity, .warning)
        XCTAssertEqual(item(AppConstants.Labels.vitalDBObserver, in: items)?.value.text, "guest-runtime-state-invalid")
        XCTAssertEqual(item(AppConstants.Labels.vitalDBObserver, in: items)?.value.severity, .warning)
    }

    func testRecorderSummaryDoesNotDisplayUnavailableObservationMetricsAsZero() {
        let observation = RuntimeContainerObservation(
            auditProxyHTTP: "200",
            auditProxyStatus: RuntimeAuditProxyStatusDocument(activeRecorderConnections: 2),
            containerLogsPresent: true,
            containerLogsBytes: 1
        )

        let summary = policy.recorderSummary(
            observation: observation,
            vitalDBObservation: nil
        )

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

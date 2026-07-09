import Contracts
import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
import Foundation
@testable import InboundAdapters

final class RuntimeStatusDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeStatusDisplayPolicy()

    func testStatusPollingIntervalUsesFastRefreshDuringActiveOperationState() {
        let pollingPolicy = RuntimeStatusPollingIntervalPolicy()
        let operationState = RuntimeOperationState(
            activeOperation: .applyBundle,
            install: .unavailable()
        )

        XCTAssertEqual(
            pollingPolicy.statusPollingIntervalNanoseconds(status: RuntimeStatus(runtimeState: .healthy), operationState: operationState),
            RuntimeStatusPollingIntervalPolicy.activeOperationInterval
        )
    }

    func testStatusPollingIntervalDoesNotInferActiveOperationFromLegacyStatusOperation() {
        let pollingPolicy = RuntimeStatusPollingIntervalPolicy()
        let status = RuntimeStatus(runtimeState: .healthy)
        let operationState = RuntimeOperationState(
            activeOperation: nil,
            install: .unavailable()
        )

        XCTAssertEqual(
            pollingPolicy.statusPollingIntervalNanoseconds(status: status, operationState: operationState),
            RuntimeStatusPollingIntervalPolicy.steadyStateInterval
        )
    }

    func testOverallHealthUsesOperationStateForActiveOperationPresentation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .present,
            runtimeState: .healthy,
        )
        let operationState = RuntimeOperationState(
            activeOperation: .applyBundle,
            install: .unavailable()
        )

        let value = policy.overallHealth(status: status, operationState: operationState)

        XCTAssertEqual(value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(value.severity, .warning)
    }

    func testOverallHealthDoesNotInferActiveOperationFromLegacyStatusOperation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            runtimeState: .healthy,
            vmIP: "192.168.64.10",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let operationState = RuntimeOperationState(
            activeOperation: nil,
            install: .unavailable()
        )

        let value = policy.overallHealth(status: status, operationState: operationState)

        XCTAssertEqual(value.text, AppConstants.StatusText.healthy)
        XCTAssertEqual(value.severity, RuntimeStatusDisplayPolicy.Severity.healthy)
    }

    func testVitalServerAvailabilityUsesOperationStateForActiveOperationPresentation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .present,
            runtimeState: .healthy,
            hostProxyHTTP: nil
        )
        let operationState = RuntimeOperationState(
            activeOperation: .applyBundle,
            install: .unavailable()
        )

        let value = policy.vitalServerAvailability(status: status, operationState: operationState)

        XCTAssertEqual(value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(value.severity, RuntimeStatusDisplayPolicy.Severity.warning)
    }

    func testVitalServerAvailabilityDoesNotInferActiveOperationFromLegacyStatusOperation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            runtimeState: .healthy,
            hostProxyHTTP: "503"
        )
        let operationState = RuntimeOperationState(
            activeOperation: nil,
            install: .unavailable()
        )

        let value = policy.vitalServerAvailability(status: status, operationState: operationState)

        XCTAssertEqual(value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(value.severity, RuntimeStatusDisplayPolicy.Severity.warning)
    }

    func testAdvancedHealthUsesOperationStateForActiveOperationPresentation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            guestLogSyncServiceState: .loaded,
            sleepPreventionServiceState: .loaded,
            watchdogServiceState: .loaded,
            runtimeState: .healthy,
            guestHTTP: "503",
            hostProxyHTTP: "503"
        )
        let operationState = RuntimeOperationState(
            activeOperation: .applyBundle,
            install: .unavailable()
        )

        let vmHealth = policy.advancedVMHealth(status: status, operationState: operationState)
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
    }

    func testAdvancedHealthDoesNotInferActiveOperationFromLegacyStatusOperation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            guestLogSyncServiceState: .loaded,
            sleepPreventionServiceState: .loaded,
            watchdogServiceState: .loaded,
            runtimeState: .updating,
            guestHTTP: "503",
            hostProxyHTTP: "503"
        )
        let operationState = RuntimeOperationState(
            activeOperation: nil,
            install: .unavailable()
        )

        let vmHealth = policy.advancedVMHealth(status: status, operationState: operationState)
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.unavailable)
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
            runtimeInstallationState: .executable,
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
        let recorderIngressStatusRead = recorderIngressStatusRead()

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
        XCTAssertNil(item(GeneratedRelease.hostProxyName, in: items)?.value.uptimeText)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: items)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: items)?.value.severity, .warning)
    }

    func testOverallHealthDoesNotDisplayUptime() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
        let value = policy.overallHealth(status: status, operationState: operationState())

        XCTAssertEqual(value.text, AppConstants.StatusText.healthy)
        XCTAssertNil(value.uptimeText)
    }

    func testUpdateOperationTakesPriorityOverTransientProxyFailures() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: false,
            watchdogServiceLoaded: true,
            runtimeState: .updating,
            guestHTTP: "000failed",
            hostProxyHTTP: nil
        )

        let operationState = operationState(activeOperation: .applyBundle)
        let overall = policy.overallHealth(status: status, operationState: operationState)
        let vitalServer = policy.vitalServerAvailability(status: status, operationState: operationState)

        XCTAssertEqual(overall.text, AppConstants.StatusText.updating)
        XCTAssertEqual(overall.severity, .warning)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.updating)
        XCTAssertEqual(vitalServer.severity, .warning)
    }

    func testInstallOperationTakesPriorityOverInitialDegradedAvailability() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            watchdogServiceLoaded: true,
            runtimeState: .installing,
            guestHTTP: "000failed",
            hostProxyHTTP: nil
        )

        let operationState = installingOperationState()
        let overall = policy.overallHealth(status: status, operationState: operationState)
        let vitalServer = policy.vitalServerAvailability(status: status, operationState: operationState)

        XCTAssertEqual(overall.text, AppConstants.StatusText.installing)
        XCTAssertEqual(overall.severity, .warning)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.installing)
        XCTAssertEqual(vitalServer.severity, .warning)
    }

    func testAdvancedServiceHealthShowsUpdatingForTransientServiceChangesDuringUpdate() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            redisUIHTTP: "503",
            swaggerUIHTTP: nil
        )
        let operationState = operationState(activeOperation: .applyBundle)
        let vmHealth = policy.advancedVMHealth(status: status, operationState: operationState)
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.stopped)
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceHealth))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(AppConstants.Labels.watchdogService, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: serviceHealth)?.value.text, AppConstants.StatusText.updating)
    }

    func testServiceHealthShowsRecoveringForApplyBundleRecovery() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
            runtimeState: .recovering,
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            redisUIHTTP: "503",
            swaggerUIHTTP: nil
        )

        let operationState = operationState(activeOperation: .applyBundle)
        let overall = policy.overallHealth(status: status, operationState: operationState)
        let vitalServer = policy.vitalServerAvailability(status: status, operationState: operationState)
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState)

        XCTAssertEqual(overall.text, AppConstants.StatusText.recovering)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.recovering)
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.recovering)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.recovering)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.recovering)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: serviceHealth)?.value.text, AppConstants.StatusText.recovering)
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: serviceHealth)?.value.text, AppConstants.StatusText.recovering)
    }

    func testAdvancedServiceHealthShowsInstallingForInitialServiceChangesDuringInstall() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            redisUIHTTP: "503",
            swaggerUIHTTP: nil
        )
        let operationState = installingOperationState()
        let vmHealth = policy.advancedVMHealth(status: status, operationState: operationState)
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState)

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceHealth))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(AppConstants.Labels.watchdogService, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: serviceHealth)?.value.text, AppConstants.StatusText.installing)
    }

    func testAdvancedServiceHealthShowsInitializingWhileRuntimeBecomesReady() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
            guestHTTP: "000failed",
            hostProxyHTTP: nil,
            redisUIHTTP: "503",
            swaggerUIHTTP: nil
        )
        let overall = policy.overallHealth(status: status, operationState: operationState(activeOperation: .runtimeDataRestore))
        let vitalServer = policy.vitalServerAvailability(status: status, operationState: operationState())
        let vmHealth = policy.advancedVMHealth(status: status, operationState: operationState())
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState())

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
            runtimeInstallationState: .executable,
            vmServiceState: .permissionDenied("launchctl denied"),
            proxyServiceState: .readFailed("launchctl failed"),
            guestLogSyncServiceState: .unknown("paused"),
            runtimeState: .updating,
        )

        let vmHealth = policy.advancedVMHealth(status: status, operationState: operationState())
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState())

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, "Permission denied")
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceHealth))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceHealth)?.value.text, "Read failed")
        XCTAssertEqual(item(AppConstants.Labels.guestLogSyncService, in: serviceHealth)?.value.text, "Paused")
    }

    func testOverallHealthDoesNotInferStartingWhenRuntimeStateIsMissing() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmIP: "192.168.64.10",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        let value = policy.overallHealth(status: status, operationState: operationState())

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
            runtimeInstallationState: .executable,
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
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .degraded,
            guestHTTP: "failed",
            hostProxyHTTP: "failed",
            failureReasons: [.guestServiceObservationMissing]
        )

        let item = policy.actionNeeded(status: status)

        XCTAssertEqual(item?.title, AppConstants.StatusText.vitalServerUnavailable)
        XCTAssertEqual(item?.recommendedAction, "Inspect logs")
        XCTAssertEqual(item?.severity, .warning)
    }

    func testActionNeededPrefersProxyRepairForProxyPortConflict() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
            runtimeInstallationState: .executable,
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
            runtimeInstallationState: .executable,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            watchdogServiceLoaded: true,
            runtimeState: .degraded,
            readIssues: [
                RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout"),
            ]
        )

        let action = policy.actionNeeded(status: status)
        let details = policy.healthDetails(status: status, operationState: operationState())

        XCTAssertNil(action)
        XCTAssertEqual(item(AppConstants.Labels.statusReadIssues, in: details)?.value.text, "hostProxyHTTP: exitCode=28 stderr=timeout")
    }

    func testStatusDisplayTextIsStandardizedAcrossSummaryAndDetails() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            vmState: .running,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let recorderIngressStatusRead = recorderIngressStatusRead()

        let summary = policy.vitalServerAvailability(status: status, operationState: operationState())
        let details = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(summary.text, AppConstants.StatusText.reachable)
        XCTAssertEqual(item(AppConstants.Labels.runtimeInstallation, in: details)?.value.text, AppConstants.StatusText.installed)
        XCTAssertEqual(item(AppConstants.Labels.vmState, in: details)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.vmState, in: details)?.value.severity, .healthy)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.text, AppConstants.StatusText.reachable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: details)?.value.text, AppConstants.StatusText.reachable)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: details)?.value.text, AppConstants.StatusText.unavailable)
    }

    func testHealthDetailsShowsGuestControlServiceStatusesWhenLoaded() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            runtimeState: .healthy,
            vmState: .running,
            guestHTTP: "200",
            hostProxyHTTP: "200",
            guestServicesReadState: .loaded,
            guestServices: ["redis", "vitaldb-observer", "redis-relay"],
            guestServiceStatuses: [
                RuntimeGuestControlServiceStatus(
                    service: "redis",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "vitaldb-observer",
                    state: "exited",
                    health: "unknown",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "redis-relay",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ],
            guestServiceResources: [
                RuntimeGuestServiceResource(
                    service: "redis",
                    spec: RuntimeGuestServiceSpec(
                        state: "configured",
                        desiredState: "running",
                        updatedAt: "2026-07-01T00:00:00Z"
                    ),
                    status: RuntimeGuestServiceStatusRead(
                        state: "loaded",
                        observedState: "running",
                        observedAt: "2026-07-01T00:00:00Z"
                    ),
                    conditions: [
                        RuntimeGuestServiceCondition(
                            type: "Reconciled",
                            status: "true",
                            reason: "DesiredStateObserved",
                            message: "matched desired state",
                            observedAt: "2026-07-01T00:00:00Z"
                        ),
                        RuntimeGuestServiceCondition(
                            type: "ResourceFresh",
                            status: "true",
                            reason: "ObservedRecently",
                            message: "resource observation is current",
                            observedAt: "2026-07-01T00:00:01Z"
                        )
                    ],
                    lastOperationId: "op-redis-reconcile-1"
                )
            ],
            guestServiceResourceReadIssues: [
                RuntimeGuestServiceResourceReadIssue(
                    service: "vitaldb-observer",
                    message: "resource document decode failed"
                )
            ],
            guestStackProbeErrors: [
                GuestRuntimeProbeError(
                    source: "docker stats",
                    message: "timed out after 1 seconds"
                )
            ]
        )

        let details = policy.healthDetails(status: status, operationState: operationState())

        XCTAssertEqual(
            item("\(AppConstants.Labels.guestProductServices): redis", in: details)?.value.text,
            "\(AppConstants.StatusText.healthy) | spec configured | desired running | status loaded | observed running | conditions Reconciled=true DesiredStateObserved: matched desired state; ResourceFresh=true ObservedRecently: resource observation is current | last operation op-redis-reconcile-1"
        )
        XCTAssertEqual(item("\(AppConstants.Labels.guestProductServices): redis", in: details)?.value.severity, .healthy)
        XCTAssertEqual(
            item("\(AppConstants.Labels.guestProductServices): vitaldb-observer", in: details)?.value.text,
            "Resource read failed: resource document decode failed"
        )
        XCTAssertEqual(
            item("\(AppConstants.Labels.guestProductServices): vitaldb-observer", in: details)?.value.severity,
            .warning
        )
        XCTAssertEqual(
            item("\(AppConstants.Labels.guestProductServices) probes", in: details)?.value.text,
            "docker stats: timed out after 1 seconds"
        )
        XCTAssertEqual(
            item("\(AppConstants.Labels.guestProductServices) probes", in: details)?.value.severity,
            .warning
        )
        XCTAssertNil(item("\(AppConstants.Labels.guestProductServices): redis-relay", in: details))
    }

    func testHealthDetailsDisplaysExplicitRuntimeInstallationState() {
        let status = RuntimeStatus(
            runtimeInstalled: false,
            runtimeInstallationState: .present,
            vmServiceState: .notLoaded
        )

        let details = policy.healthDetails(status: status, operationState: operationState())
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

        let overall = policy.overallHealth(status: status, operationState: operationState())
        let vitalServer = policy.vitalServerAvailability(status: status, operationState: operationState())
        let actionNeeded = policy.actionNeeded(status: status)

        XCTAssertEqual(overall.text, "Present but not executable")
        XCTAssertEqual(overall.severity, .critical)
        XCTAssertEqual(vitalServer.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(vitalServer.severity, .critical)
        XCTAssertEqual(actionNeeded?.title, "Present but not executable")
        XCTAssertEqual(actionNeeded?.recommendedAction, AppConstants.Actions.openLogs)
        XCTAssertEqual(actionNeeded?.severity, .critical)
    }

    func testOverallHealthShowsRecoveringDuringRuntimeDataRestoreProgress() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .recovering,
            guestHTTP: "failed",
            hostProxyHTTP: "failed"
        )

        let overall = policy.overallHealth(status: status, operationState: operationState())

        XCTAssertEqual(overall.text, AppConstants.StatusText.recovering)
        XCTAssertEqual(overall.severity, RuntimeStatusDisplayPolicy.Severity.warning)
    }

    func testUptimePrefersExplicitSecondsOverDockerStartedAt() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let recorderIngressStatusRead = recorderIngressStatusRead()
        let now = ISO8601DateFormatter().date(from: "2026-05-26T04:35:40Z")!

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead, now: now)

        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
    }

    func testUptimeTicksExplicitSecondsFromHostObservedAtForDisplay() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let now = ISO8601DateFormatter().date(from: "2026-06-13T00:00:05Z")!

        let items = policy.advancedServiceHealth(status: status, operationState: operationState(), now: now)

        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
    }

    func testUptimeDoesNotTickExplicitSecondsFromStaleGuestUpdatedAtWhenHostObservedAtIsMissing() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let now = ISO8601DateFormatter().date(from: "2026-06-13T00:00:00Z")!

        let items = policy.advancedServiceHealth(status: status, operationState: operationState(), now: now)

        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
    }

    func testUptimeUsesDockerStartedAtWithNanosecondFractionWhenExplicitSecondsAreMissing() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let recorderIngressStatusRead = recorderIngressStatusRead()
        let now = ISO8601DateFormatter().date(from: "2026-05-26T04:35:40Z")!

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead, now: now)

        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
    }

    func testUptimeUsesExplicitSecondsWhenStartedAtIsMissing() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let recorderIngressStatusRead = recorderIngressStatusRead()
        let now = ISO8601DateFormatter().date(from: "2026-05-26T04:35:40Z")!

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead, now: now)

        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
    }

    func testUptimeDisplaysDaysBeforeClockDuration() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let recorderIngressStatusRead = recorderIngressStatusRead()

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
    }

    func testAdvancedServiceHealthOwnsLabelsActionsAndHTTPStatusDisplay() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
        let items = policy.advancedServiceHealth(status: status, operationState: operationState())

        XCTAssertEqual(items.map(\.label), [
            AppConstants.Labels.proxyService,
            AppConstants.Labels.guestLogSyncService,
            AppConstants.Labels.sleepPreventionService,
            AppConstants.Labels.watchdogService,
            AppConstants.Labels.guestProductServices,
            AppConstants.Labels.redisRelay,
            GeneratedRelease.vitalServerName,
            GeneratedRelease.hostProxyName,
            GeneratedRelease.redisUIName,
            GeneratedRelease.swaggerUIName,
        ])
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: items)?.action, .openVitalServer)
        XCTAssertNil(item(GeneratedRelease.vitalServerName, in: items)?.value.uptimeText)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: items)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: items)?.httpStatus, "503")
        XCTAssertEqual(item(AppConstants.Labels.guestLogSyncService, in: items)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.sleepPreventionService, in: items)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.text, AppConstants.StatusText.disabled)
        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.severity, .neutral)
        XCTAssertEqual(item(GeneratedRelease.redisUIName, in: items)?.action, .openRedisUI)
        XCTAssertEqual(item(GeneratedRelease.swaggerUIName, in: items)?.action, .openSwagger)
    }

    func testAdvancedServiceHealthShowsGuestControlServiceStatusesWhenLoaded() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            guestServicesReadState: .loaded,
            guestServices: ["app", "recorder-ingress"],
            guestServiceStatuses: [
                RuntimeGuestControlServiceStatus(
                    service: "recorder-ingress",
                    state: "running",
                    health: "unhealthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ],
            guestServiceResources: [
                RuntimeGuestServiceResource(
                    service: "app",
                    spec: RuntimeGuestServiceSpec(
                        state: "configured",
                        desiredState: "running",
                        updatedAt: "2026-07-01T00:00:00Z"
                    ),
                    status: RuntimeGuestServiceStatusRead(
                        state: "loaded",
                        observedState: "running",
                        observedAt: "2026-07-01T00:00:00Z"
                    ),
                    conditions: [
                        RuntimeGuestServiceCondition(
                            type: "Reconciled",
                            status: "true",
                            reason: "DesiredStateObserved",
                            message: "matched desired state",
                            observedAt: "2026-07-01T00:00:00Z"
                        ),
                        RuntimeGuestServiceCondition(
                            type: "ResourceFresh",
                            status: "true",
                            reason: "ObservedRecently",
                            message: "resource observation is current",
                            observedAt: "2026-07-01T00:00:01Z"
                        )
                    ],
                    lastOperationId: "op-app-reconcile-1"
                )
            ],
            guestServiceResourceReadIssues: [
                RuntimeGuestServiceResourceReadIssue(
                    service: "recorder-ingress",
                    message: "resource controller unavailable"
                )
            ],
            guestStackProbeErrors: [
                GuestRuntimeProbeError(
                    source: "docker stats",
                    message: "timed out after 1 seconds"
                )
            ]
        )
        let items = policy.advancedServiceHealth(status: status, operationState: operationState())

        let appLabel = "\(AppConstants.Labels.guestProductServices): app"
        let recorderIngressLabel = "\(AppConstants.Labels.guestProductServices): recorder-ingress"
        let app = item(appLabel, in: items)
        let recorderIngress = item(recorderIngressLabel, in: items)
        XCTAssertEqual(
            app?.value.text,
            "\(AppConstants.StatusText.healthy) | spec configured | desired running | status loaded | observed running | conditions Reconciled=true DesiredStateObserved: matched desired state; ResourceFresh=true ObservedRecently: resource observation is current | last operation op-app-reconcile-1"
        )
        XCTAssertEqual(app?.value.severity, .healthy)
        XCTAssertEqual(recorderIngress?.value.text, "Resource read failed: resource controller unavailable")
        XCTAssertEqual(recorderIngress?.value.severity, .warning)
        XCTAssertEqual(
            item("\(AppConstants.Labels.guestProductServices) probes", in: items)?.value.text,
            "docker stats: timed out after 1 seconds"
        )
        XCTAssertEqual(
            item("\(AppConstants.Labels.guestProductServices) probes", in: items)?.value.severity,
            .warning
        )
        XCTAssertLessThan(
            items.firstIndex { $0.label == appLabel } ?? Int.max,
            items.firstIndex { $0.label == recorderIngressLabel } ?? Int.max
        )
        XCTAssertNil(item(AppConstants.Labels.vitalDBObserver, in: items))
        XCTAssertNil(item(GeneratedRelease.recorderRecoveryName, in: items))
    }

    func testAdvancedServiceHealthUsesGuestControlStatusForRedisRelayWithoutDuplicateGuestServiceItem() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            guestServicesReadState: .loaded,
            guestServices: ["app", "redis-relay"],
            guestServiceStatuses: [
                RuntimeGuestControlServiceStatus(
                    service: "redis-relay",
                    state: "running",
                    health: "unhealthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-01T00:00:00Z"
                ),
            ],
            redisRelayStatus: RuntimeRedisRelayStatus(
                observedAt: "2026-06-18T00:00:00Z",
                enabled: true,
                state: "failed",
                scope: "vital_reconstruction",
                lastError: "legacy status file should not own service liveness"
            )
        )
        let items = policy.advancedServiceHealth(
            status: status,
            operationState: operationState(),
            redisRelaySettings: RuntimeRedisRelaySettings(enabled: true)
        )

        XCTAssertEqual(
            item(AppConstants.Labels.redisRelay, in: items)?.value.text,
            AppConstants.StatusText.containerHealth("unhealthy")
        )
        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.severity, .warning)
        XCTAssertNil(item("\(AppConstants.Labels.guestProductServices): redis-relay", in: items))
        XCTAssertEqual(item("\(AppConstants.Labels.guestProductServices): app", in: items)?.value.text, AppConstants.StatusText.healthy)
    }

    func testAdvancedServiceHealthShowsGuestControlReadFailureSeparately() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            guestServicesReadState: .failed,
            guestServicesReadError: "guest control api timed out"
        )
        let items = policy.advancedServiceHealth(status: status, operationState: operationState())

        let guestServices = item(AppConstants.Labels.guestProductServices, in: items)
        XCTAssertEqual(guestServices?.value.text, "guest control api timed out")
        XCTAssertEqual(guestServices?.value.severity, .warning)
        XCTAssertNil(item("\(AppConstants.Labels.guestProductServices): app", in: items))
        XCTAssertNil(item(AppConstants.Labels.vitalDBObserver, in: items))
        XCTAssertNil(item(GeneratedRelease.recorderIngressName, in: items))
    }

    func testAdvancedServiceHealthShowsRedisRelayHealthyWhenEnabledAndHealthy() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            redisRelayStatus: RuntimeRedisRelayStatus(
                observedAt: "2026-06-18T00:00:00Z",
                enabled: true,
                state: "running",
                scope: "vital_reconstruction"
            )
        )
        let settings = RuntimeRedisRelaySettings(enabled: true)
        let items = policy.advancedServiceHealth(
            status: status,
            operationState: operationState(),
            redisRelaySettings: settings
        )

        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.text, AppConstants.StatusText.running)
        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.severity, .healthy)
        XCTAssertNil(item(AppConstants.Labels.redisRelay, in: items)?.value.uptimeText)
    }

    func testAdvancedServiceHealthShowsRedisRelayDisabledFromSettingsBeforeStaleStatus() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            redisRelayStatus: RuntimeRedisRelayStatus(
                observedAt: "2026-06-18T00:00:00Z",
                enabled: true,
                state: "running",
                scope: "vital_reconstruction"
            )
        )

        let items = policy.advancedServiceHealth(
            status: status,
            operationState: operationState(),
            redisRelaySettings: RuntimeRedisRelaySettings(enabled: false)
        )

        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.text, AppConstants.StatusText.disabled)
        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.severity, .neutral)
    }

    func testAdvancedServiceHealthShowsRedisRelayFailureWhenEnabledStatusReportsError() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            redisRelayStatus: RuntimeRedisRelayStatus(
                observedAt: "2026-06-18T00:00:00Z",
                enabled: true,
                state: "failed",
                scope: "vital_reconstruction",
                lastError: "target redis auth failed"
            )
        )
        let settings = RuntimeRedisRelaySettings(enabled: true)
        let items = policy.advancedServiceHealth(
            status: status,
            operationState: operationState(),
            redisRelaySettings: settings
        )

        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.text, AppConstants.StatusText.failed)
        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.value.severity, .warning)
        XCTAssertEqual(item(AppConstants.Labels.redisRelay, in: items)?.httpStatus, "target redis auth failed")
    }

    func testAdvancedServiceHealthUsesTypedServiceStateBeforeLegacyLoadedBool() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            guestLogSyncServiceLoaded: false,
            watchdogServiceLoaded: false,
            vmServiceState: .permissionDenied("launchctl denied"),
            proxyServiceState: .notLoaded,
            guestLogSyncServiceState: .readFailed("launchctl failed"),
            watchdogServiceState: .loaded
        )

        let vmItems = policy.advancedVMHealth(status: status, operationState: operationState())
        let serviceItems = policy.advancedServiceHealth(status: status, operationState: operationState())

        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmItems)?.value.text, "Permission denied")
        XCTAssertNil(item(AppConstants.Labels.vmService, in: serviceItems))
        XCTAssertEqual(item(AppConstants.Labels.proxyService, in: serviceItems)?.value.text, AppConstants.StatusText.stopped)
        XCTAssertEqual(item(AppConstants.Labels.guestLogSyncService, in: serviceItems)?.value.text, "Read failed")
        XCTAssertEqual(item(AppConstants.Labels.watchdogService, in: serviceItems)?.value.text, AppConstants.StatusText.running)
    }

    func testServiceDisplayDoesNotInferLaunchdStateFromLegacyLoadedBools() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: false,
            proxyServiceLoaded: false,
            guestLogSyncServiceLoaded: false,
            watchdogServiceLoaded: false,
            guestHTTP: "failed",
            hostProxyHTTP: nil
        )

        let healthDetails = policy.healthDetails(status: status, operationState: operationState())
        let vmHealth = policy.advancedVMHealth(status: status, operationState: operationState())
        let serviceHealth = policy.advancedServiceHealth(status: status, operationState: operationState())

        XCTAssertEqual(item(AppConstants.Labels.watchdog, in: healthDetails)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(AppConstants.Labels.vmService, in: vmHealth)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceHealth)?.value.text, AppConstants.StatusText.unreachable)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceHealth)?.value.text, AppConstants.StatusText.notReported)
    }

    func testAdvancedVMHealthSeparatesVMIntegrityFromServiceLiveness() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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

        let vmItems = policy.advancedVMHealth(status: status, operationState: operationState())
        let serviceItems = policy.advancedServiceHealth(status: status, operationState: operationState())

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

    func testRuntimeStateStaleDoesNotDriveGuestReadinessWaitingPresentation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
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
            vmErrors: [.guestHTTP(RuntimeHTTPStatusText.missingVMIP)],
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            hostProxyHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: [.guestHTTP(RuntimeHTTPStatusText.missingVMIP)]
        )

        let details = policy.healthDetails(status: status, operationState: operationState())
        let vmItems = policy.advancedVMHealth(status: status, operationState: operationState())
        let serviceItems = policy.advancedServiceHealth(status: status, operationState: operationState())

        XCTAssertEqual(item(AppConstants.Labels.vmIPAddress, in: details)?.value.text, AppConstants.StatusText.waiting)
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: details)?.value.text, "Guest HTTP missing-vm-ip")
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: details)?.value.severity, .warning)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.text, AppConstants.StatusText.waiting)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.severity, .warning)
        XCTAssertEqual(item(AppConstants.Labels.vmIPAddress, in: vmItems)?.value.text, AppConstants.StatusText.waiting)
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: vmItems)?.value.text, "Guest HTTP missing-vm-ip")
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: vmItems)?.value.severity, .warning)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.value.text, AppConstants.StatusText.waiting)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.value.severity, .warning)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: serviceItems)?.httpStatus, RuntimeHTTPStatusText.missingVMIP)
        XCTAssertEqual(item(GeneratedRelease.hostProxyName, in: serviceItems)?.value.text, AppConstants.StatusText.reachable)
    }

    func testHealthDetailsUsesOperationStateForGuestReadinessPresentation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            vmState: .starting,
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            hostProxyHTTP: "200"
        )
        let operationState = RuntimeOperationState(
            activeOperation: .applyBundle,
            install: .unavailable()
        )

        let details = policy.healthDetails(status: status, operationState: operationState)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.text, AppConstants.StatusText.failed)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.severity, .warning)
    }

    func testHealthDetailsDoesNotInferGuestReadinessOperationFromLegacyStatusOperation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            runtimeState: .updating,
            vmState: .starting,
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            hostProxyHTTP: "200"
        )
        let operationState = RuntimeOperationState(
            activeOperation: nil,
            install: .unavailable()
        )

        let details = policy.healthDetails(status: status, operationState: operationState)

        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.text, AppConstants.StatusText.waiting)
        XCTAssertEqual(item(GeneratedRelease.vitalServerName, in: details)?.value.severity, .warning)
    }

    func testGuestStateStaleAfterVMRunningRemainsFailurePresentation() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            vmState: .running,
            vmErrors: [.guestHTTP(RuntimeHTTPStatusText.missingVMIP)],
            guestHTTP: RuntimeHTTPStatusText.missingVMIP,
            hostProxyHTTP: "200",
            failureReasons: [.guestHTTP(RuntimeHTTPStatusText.missingVMIP)]
        )

        let details = policy.healthDetails(status: status, operationState: operationState())
        let vmItems = policy.advancedVMHealth(status: status, operationState: operationState())
        let serviceItems = policy.advancedServiceHealth(status: status, operationState: operationState())

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
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            vmState: .stale,
            vmErrors: [.guestFilesystemError, .diskAttachmentInvalid, .guestDiskIO, .guestHTTP("failed")]
        )

        let items = policy.healthDetails(status: status, operationState: operationState())

        XCTAssertEqual(
            item(AppConstants.Labels.vmErrors, in: items)?.value.text,
            "Guest filesystem error, VM disk attachment invalid, Guest disk I/O error, Guest HTTP failed"
        )
        XCTAssertEqual(item(AppConstants.Labels.vmErrors, in: items)?.value.severity, .critical)
    }

    func testHealthDetailsDisplayDomainFailureReasonsWhenPresent() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            failureReasons: [.hostProxyHTTP("503"), .guestServiceObservationMissing]
        )

        let items = policy.healthDetails(status: status, operationState: operationState())

        XCTAssertEqual(
            item(AppConstants.Labels.failureReasons, in: items)?.value.text,
            "Host proxy HTTP 503 (Restart host proxy service), Guest service observation missing (Inspect logs)"
        )
        XCTAssertEqual(item(AppConstants.Labels.failureReasons, in: items)?.value.severity, .critical)
    }

    func testRecorderSummaryOwnsRecorderDisplayText() {
        let recorderIngressStatusRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
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
            readError: nil
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
            recorderIngressStatusRead: recorderIngressStatusRead,
            vitalDBObservation: vitalDBObservation,
            now: ISO8601DateFormatter().date(from: "2026-05-24T02:00:00Z")!
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
            recorderIngressStatusRead: nil,
            vitalDBObservation: vitalDBObservation
        )

        XCTAssertEqual(summary.latestRecorder, "VR_NO_IP \(AppConstants.StatusText.notReported)")
    }

    func testRecorderSummaryUsesCurrentTimeForOnlineCounts() {
        let vitalDBObservation = VitalDBObservationDocument(
            observedAt: "2026-05-24T02:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_AGED",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-24T01:59:59Z",
                    online: true
                ),
            ]
        )

        let summary = policy.recorderSummary(
            recorderIngressStatusRead: nil,
            vitalDBObservation: vitalDBObservation,
            now: ISO8601DateFormatter().date(from: "2026-05-24T02:10:00Z")!
        )

        XCTAssertEqual(summary.onlineRecorders, "0")
        XCTAssertEqual(summary.staleRecorders, "1")
    }

    func testVitalServerUptimeDoesNotFallBackToStatusStartedAt() {
        let now = ISO8601DateFormatter().date(from: "2026-05-29T00:02:05Z")!
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        let value = policy.vitalServerAvailability(status: status, operationState: operationState(), now: now)

        XCTAssertNil(value.uptimeText)
    }

    func testGuestProductServicesAreUnavailableWithoutGuestServiceRead() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let recorderIngressStatusRead = recorderIngressStatusRead()

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: items)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: items)?.value.severity, .warning)
    }

    func testRecorderIngressQueueDisplaysHealthyStatus() {
        let status = healthyRuntimeStatus()
        let recorderIngressStatusRead = recorderIngressStatusRead(
            document: RuntimeRecorderIngressStatusDocument(
                spool: RuntimeRecorderIngressSpoolStatus(
                    status: "ready",
                    rejectedEvents: 0,
                    writeFailures: 0,
                    pendingItems: 0,
                    pendingBytes: 0
                ),
                replay: RuntimeRecorderIngressReplayStatus(
                    status: "idle",
                    pendingItems: 0,
                    inFlightItems: 0,
                    retryableFailures: 0,
                    deadLetteredEvents: 0
                )
            )
        )

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.text, "healthy, 0 pending")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.severity, .healthy)
    }

    func testRecorderIngressQueueStatusValueIsAvailableForStatusPanel() {
        let recorderIngressStatusRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                spool: RuntimeRecorderIngressSpoolStatus(
                    status: "ready",
                    pendingItems: 7
                ),
                replay: RuntimeRecorderIngressReplayStatus(status: "replaying")
            ),
            readError: nil
        )

        let value = policy.recorderIngressQueue(recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(value.text, "draining, 7 pending")
        XCTAssertEqual(value.severity, .warning)
    }

    func testRecorderIngressDetailsDisplayOperationalRows() {
        let recorderIngressStatusRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                activeWebSockets: 3,
                activeRecorderConnections: 2,
                throughput: RuntimeRecorderIngressThroughputStatus(
                    observedBytesPerSecond: 5_242_880,
                    spooledBytesPerSecond: 5_242_880,
                    replayedBytesPerSecond: 4_194_304,
                    queueGrowthBytesPerSecond: 1_048_576
                ),
                spool: RuntimeRecorderIngressSpoolStatus(
                    status: "ready",
                    rejectedEvents: 2,
                    writeFailures: 0,
                    pendingItems: 128,
                    pendingBytes: 24_000_000,
                    oldestPendingAgeSeconds: 34
                ),
                replay: RuntimeRecorderIngressReplayStatus(
                    status: "replaying",
                    inFlightItems: 1,
                    retryableFailures: 0,
                    deadLetteredEvents: 0,
                    replayLagSeconds: 12,
                    maxBytesPerSecond: 4 * 1_048_576,
                    adaptive: RuntimeRecorderIngressReplayAdaptiveStatus(
                        enabled: true,
                        minBytesPerSecond: 2 * 1_048_576,
                        maxBytesPerSecond: 12 * 1_048_576,
                        currentItemsPerTick: 500,
                        currentConcurrency: 8,
                        memoryGuardStatus: .healthy
                    )
                )
            ),
            readError: nil
        )

        let items = policy.recorderIngressDetails(recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.recorderIngressConnections, in: items)?.value.text, "2 active / 3 WebSockets")
        XCTAssertEqual(item(AppConstants.Labels.queue, in: items)?.value.text, "128 pending / 24 MB")
        XCTAssertEqual(item(AppConstants.Labels.queue, in: items)?.value.severity, .warning)
        XCTAssertEqual(
            item(AppConstants.Labels.recorderIngressThroughput, in: items)?.value.text,
            "in 5.2 MB/s, replay 4.2 MB/s, queue +1 MB/s"
        )
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressOldestPending, in: items)?.value.text, "34s")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: items)?.value.text, "replaying")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: items)?.value.severity, .healthy)
        XCTAssertEqual(
            item(AppConstants.Labels.recorderIngressReplayThroughput, in: items)?.value.text,
            "4.0 MiB/s, adaptive 2.0 MiB/s-12.0 MiB/s, guard healthy, 500 items/tick, concurrency 8"
        )
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressInFlight, in: items)?.value.text, "1")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplayLag, in: items)?.value.text, "12s")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressBackpressureRejected, in: items)?.value.text, "2")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressBackpressureRejected, in: items)?.value.severity, .warning)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressRetryableFailures, in: items)?.value.text, "0")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressRetryableFailures, in: items)?.value.severity, .healthy)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressDeadLetters, in: items)?.value.text, "0")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressDeadLetters, in: items)?.value.severity, .healthy)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressLastFailure, in: items)?.value.text, "none")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressLastFailure, in: items)?.value.severity, .healthy)
    }

    func testRecorderIngressDetailsDoNotDefaultMissingQueueFieldsToZero() {
        let recorderIngressStatusRead = recorderIngressStatusRead(
            document: RuntimeRecorderIngressStatusDocument(activeRecorderConnections: 2)
        )

        let items = policy.recorderIngressDetails(recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.recorderIngressConnections, in: items)?.value.text, "2 active / 0 WebSockets")
        XCTAssertEqual(item(AppConstants.Labels.queue, in: items)?.value.text, AppConstants.StatusText.notReported)
        XCTAssertEqual(item(AppConstants.Labels.queue, in: items)?.value.severity, .neutral)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: items)?.value.text, AppConstants.StatusText.notReported)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: items)?.value.severity, .neutral)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressBackpressureRejected, in: items)?.value.text, AppConstants.StatusText.notReported)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressBackpressureRejected, in: items)?.value.severity, .neutral)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressDeadLetters, in: items)?.value.text, AppConstants.StatusText.notReported)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressDeadLetters, in: items)?.value.severity, .neutral)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressLastFailure, in: items)?.value.text, AppConstants.StatusText.notReported)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressLastFailure, in: items)?.value.severity, .neutral)
    }

    func testRecorderIngressQueueDisplaysDrainingBacklog() {
        let status = healthyRuntimeStatus()
        let recorderIngressStatusRead = recorderIngressStatusRead(
            document: RuntimeRecorderIngressStatusDocument(
                spool: RuntimeRecorderIngressSpoolStatus(
                    status: "ready",
                    rejectedEvents: 0,
                    writeFailures: 0,
                    pendingItems: 128,
                    oldestPendingAgeSeconds: 34
                ),
                replay: RuntimeRecorderIngressReplayStatus(
                    status: "replaying",
                    inFlightItems: 1,
                    retryableFailures: 0,
                    deadLetteredEvents: 0,
                    replayLagSeconds: 12
                )
            )
        )

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(
            item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.text,
            "draining, 128 pending, 1 in flight, oldest 34s, replay lag 12s"
        )
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.severity, .warning)
    }

    func testRecorderIngressQueueDisplaysMirrorSpoolAsMirroringNotDraining() {
        let recorderIngressStatusRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(
                spool: RuntimeRecorderIngressSpoolStatus(
                    mode: "mirror_spool",
                    status: "ready",
                    rejectedEvents: 0,
                    writeFailures: 0,
                    pendingItems: 128,
                    pendingBytes: 24_000_000,
                    oldestPendingAgeSeconds: 34
                ),
                replay: RuntimeRecorderIngressReplayStatus(
                    status: "disabled",
                    inFlightItems: 0,
                    retryableFailures: 0,
                    deadLetteredEvents: 0
                )
            ),
            readError: nil
        )

        let summary = policy.recorderIngressQueue(recorderIngressStatusRead: recorderIngressStatusRead)
        let details = policy.recorderIngressDetails(recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(
            summary.text,
            "mirroring, 128 pending, 24 MB, oldest 34s, replay disabled"
        )
        XCTAssertEqual(summary.severity, .neutral)
        XCTAssertEqual(item(AppConstants.Labels.queue, in: details)?.value.text, "128 pending / 24 MB")
        XCTAssertEqual(item(AppConstants.Labels.queue, in: details)?.value.severity, .neutral)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: details)?.value.text, "disabled")
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: details)?.value.severity, .neutral)
    }

    func testRecorderIngressQueueDisplaysFailureEvidence() {
        let status = healthyRuntimeStatus()
        let recorderIngressStatusRead = recorderIngressStatusRead(
            document: RuntimeRecorderIngressStatusDocument(
                spool: RuntimeRecorderIngressSpoolStatus(
                    status: "ready",
                    rejectedEvents: 2,
                    writeFailures: 0
                ),
                replay: RuntimeRecorderIngressReplayStatus(
                    status: "degraded",
                    retryableFailures: 4,
                    deadLetteredEvents: 0,
                    lastFailure: RuntimeRecorderIngressFailureObservation(reason: "upstream_timeout")
                )
            )
        )

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(
            item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.text,
            "degraded, 2 rejected, 4 retryable failures, last failure upstream_timeout"
        )
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.severity, .warning)
    }

    func testRecorderIngressQueueDisplaysCriticalDeadLetters() {
        let status = healthyRuntimeStatus()
        let recorderIngressStatusRead = recorderIngressStatusRead(
            document: RuntimeRecorderIngressStatusDocument(
                spool: RuntimeRecorderIngressSpoolStatus(
                    status: "ready",
                    writeFailures: 0,
                    pendingItems: 0
                ),
                replay: RuntimeRecorderIngressReplayStatus(
                    status: "degraded",
                    deadLetteredEvents: 3,
                    lastFailure: RuntimeRecorderIngressFailureObservation(reason: "invalid_payload")
                )
            )
        )

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(
            item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.text,
            "degraded, 3 dead letters, last failure invalid_payload"
        )
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.severity, .critical)
    }

    func testRecorderIngressQueueDoesNotDefaultMissingQueueStateToZero() {
        let status = healthyRuntimeStatus()
        let recorderIngressStatusRead = recorderIngressStatusRead(
            document: RuntimeRecorderIngressStatusDocument(activeRecorderConnections: 2)
        )

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.text, AppConstants.StatusText.notReported)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.severity, .neutral)
    }

    func testRecorderIngressQueueDisplaysStatusReadFailureAsNotReady() {
        let status = healthyRuntimeStatus()
        let recorderIngressStatusRead = recorderIngressStatusRead(
            readState: .commandFailed,
            httpStatus: "failed",
            readError: "curl failed"
        )

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.text, AppConstants.StatusText.notReady)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressQueue, in: items)?.value.severity, .warning)
    }

    func testRecorderIngressDetailsDisplaysStatusReadFailureAsNotReady() {
        let recorderIngressStatusRead = recorderIngressStatusRead(
            readState: .commandFailed,
            httpStatus: "failed",
            readError: "command-failed-7 exitCode=7 stderr=curl failed"
        )

        let items = policy.recorderIngressDetails(recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: items)?.value.text, AppConstants.StatusText.notReady)
        XCTAssertEqual(item(AppConstants.Labels.recorderIngressReplay, in: items)?.value.severity, .warning)
    }

    func testGuestProductServicesStayUnavailableWhenGuestServiceReadIsMissing() {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
        let recorderIngressStatusRead = recorderIngressStatusRead()

        let items = policy.healthDetails(status: status, operationState: operationState(), recorderIngressStatusRead: recorderIngressStatusRead)

        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: items)?.value.text, AppConstants.StatusText.unavailable)
        XCTAssertEqual(item(AppConstants.Labels.guestProductServices, in: items)?.value.severity, .warning)
    }

    func testRecorderSummaryDoesNotDisplayUnavailableObservationMetricsAsZero() {
        let recorderIngressStatusRead = RuntimeRecorderIngressStatusReadResult(
            readState: .loaded,
            httpStatus: "200",
            document: RuntimeRecorderIngressStatusDocument(activeRecorderConnections: 2),
            readError: nil
        )

        let summary = policy.recorderSummary(
            recorderIngressStatusRead: recorderIngressStatusRead,
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

    private func healthyRuntimeStatus() -> RuntimeStatus {
        RuntimeStatus(
            runtimeInstalled: true,
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )
    }

    private func recorderIngressStatusRead(
        readState: RuntimeRecorderIngressStatusReadState = .loaded,
        httpStatus: String = "200",
        document: RuntimeRecorderIngressStatusDocument? = nil,
        readError: String? = nil
    ) -> RuntimeRecorderIngressStatusReadResult {
        RuntimeRecorderIngressStatusReadResult(
            readState: readState,
            httpStatus: httpStatus,
            document: document,
            readError: readError
        )
    }

    private func operationState(activeOperation: RuntimeOperation? = nil) -> RuntimeOperationState {
        RuntimeOperationState(
            activeOperation: activeOperation,
            install: .unavailable()
        )
    }

    private func installingOperationState() -> RuntimeOperationState {
        RuntimeOperationState(
            activeOperation: nil,
            install: .loaded(RuntimeInstallStateDocument(
                state: .stepStarted,
                mode: .full,
                updatedAt: "2026-07-08T00:00:00Z",
                message: "installing"
            )),
            lease: .loaded(RuntimeOperationLeaseDocument(
                operationId: "install-operation",
                operation: .install,
                ownerPID: nil,
                startedAt: "2026-07-08T00:00:00Z",
                heartbeatAt: "2026-07-08T00:00:00Z",
                expiresAt: nil,
                message: "installing"
            ))
        )
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

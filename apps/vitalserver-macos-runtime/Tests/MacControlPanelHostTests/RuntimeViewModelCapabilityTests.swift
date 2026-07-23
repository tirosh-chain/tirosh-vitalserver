import Foundation
import Contracts
import Application
import Domain
import RuntimeControl
@testable import MacControlPanelHost
import MacPlatformAgent
import SwiftUI
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeViewModelCapabilityTests: XCTestCase {
    func testViewModelInitializesStatusFromExplicitControlClientRead() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.status = platformState(runtimeInstallationState: .executable, runtimeVersion: "initial-version")

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadStatusCount, 1)
        XCTAssertEqual(viewModel.status.installedVersion, "initial-version")
        XCTAssertEqual(viewModel.status.runtimeInstallationState.isExecutable, true)
    }

    func testViewModelInitialSettingsResolutionUsesControlSettingsAsPortOwner() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.settings.runtimeControlPort = 44080

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadSettingsCount, 1)
        XCTAssertEqual(viewModel.settings.runtimeControlPort, 44080)
    }

    func testPlatformSettingsOwnerFailureRemainsAnExplicitFailedPresentationState() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.settings = RuntimeSettings(readIssues: [
            RuntimeSettingsReadIssue(
                source: "platformSettings",
                message: "Platform Agent API unavailable"
            )
        ])

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(
            viewModel.platformSettingsReadState,
            .failed([RuntimeSettingsReadIssue(
                source: "platformSettings",
                message: "Platform Agent API unavailable"
            )])
        )
        XCTAssertFalse(viewModel.canDisplayPlatformSettings)
        XCTAssertEqual(viewModel.platformSettingsReadIssues.map(\.source), ["platformSettings"])
    }

    func testViewModelInitialSettingsUsesExplicitInputWithoutControlSettingsRead() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var initialSettings = RuntimeSettings()
        initialSettings.runtimeControlPort = 44080

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            initialSettings: initialSettings,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadSettingsCount, 0)
        XCTAssertEqual(viewModel.settings.runtimeControlPort, 44080)
    }

    func testViewModelInitialSettingsPreserveExplicitEmptyAdvertisedServiceURLs() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var initialSettings = RuntimeSettings()
        initialSettings.proxyPort = 18080
        initialSettings.runtimeControlPort = 18322
        initialSettings.vitalServerURL = ""
        initialSettings.remoteConsoleURL = " "

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            initialSettings: initialSettings,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(viewModel.settings.vitalServerURL, "")
        XCTAssertEqual(viewModel.settings.remoteConsoleURL, " ")
    }

    func testViewModelUsesExplicitInitialStatusWithoutPlaceholderRead() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            initialStatus: platformState(runtimeInstallationState: .executable, runtimeVersion: "provided"),
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadStatusCount, 0)
        XCTAssertEqual(viewModel.status.installedVersion, "provided")
        XCTAssertEqual(viewModel.status.runtimeInstallationState.isExecutable, true)
    }

    func testRedisRelayRefreshUsesDirectRuntimeOwnerResource() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let document = RuntimeRedisRelayStatus(
            observedAt: "2026-07-11T00:00:00Z",
            enabled: true,
            state: "running",
            scope: "vital_reconstruction"
        )
        client.redisRelayStatusRead = RuntimeRedisRelayStatusReadResult(
            readState: .loaded,
            document: document,
            readError: nil
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshRedisRelayStatus()

        XCTAssertEqual(client.loadRedisRelayStatusCount, 1)
        XCTAssertEqual(viewModel.redisRelayStatusRead.document, document)
        XCTAssertEqual(viewModel.redisRelayStatusRead.readState, .loaded)
    }

    func testRedisRelayRefreshPreservesDirectResourceReadFailure() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.redisRelayStatusError = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "runtime owner unavailable"]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshRedisRelayStatus()

        XCTAssertEqual(viewModel.redisRelayStatusRead.readState, .readFailed)
        XCTAssertNil(viewModel.redisRelayStatusRead.document)
        XCTAssertEqual(viewModel.redisRelayStatusRead.readError, "runtime owner unavailable")
    }

    func testRefreshLoadsRedisRelaySettingsFromRuntimeOwnerInsteadOfHostSettings() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.settings.redisRelay.enabled = false
        client.runtimeRedisRelaySettingsRead = loadedRedisRelaySettings(enabled: true)
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.runtimeRedisRelaySettingsRead.state, .loaded)
        XCTAssertTrue(viewModel.settings.redisRelay.enabled)
        XCTAssertTrue(viewModel.canEditRuntimeRedisRelaySettings)
    }

    func testApplySettingsSendsRedisRelayChangeToRuntimeOwner() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.runtimeRedisRelaySettingsRead = loadedRedisRelaySettings(enabled: false)
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        await viewModel.refresh()
        viewModel.settings.redisRelay.enabled = true
        viewModel.settings.redisRelay.target.password = "new-secret"

        await viewModel.applySettings()

        XCTAssertEqual(client.appliedRuntimeRedisRelaySettings.count, 1)
        XCTAssertTrue(client.appliedRuntimeRedisRelaySettings[0].enabled)
        XCTAssertEqual(client.appliedRuntimeRedisRelaySettings[0].target.password, "new-secret")
        XCTAssertEqual(client.applySettingsCount, 1)
    }

    func testRuntimeStackRefreshUsesDirectStackAndServiceResources() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.runtimeStackStatus = RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-07-11T00:00:00Z",
            services: [
                RuntimeGuestControlServiceStatus(
                    service: "app",
                    state: "running",
                    health: "healthy",
                    observedAt: "2026-07-11T00:00:00Z"
                ),
                RuntimeGuestControlServiceStatus(
                    service: "worker",
                    state: "running",
                    health: "unknown",
                    observedAt: "2026-07-11T00:00:00Z"
                ),
            ]
        )
        client.serviceResourcesByService["app"] = runtimeServiceResource(service: "app")
        client.serviceResourceErrorsByService["worker"] = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "resource owner unavailable"]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshRuntimeStack()

        XCTAssertEqual(client.runtimeStackStatusCount, 1)
        XCTAssertEqual(client.serviceResourceRequests, ["app", "worker"])
        XCTAssertEqual(viewModel.runtimeStackStatus, client.runtimeStackStatus)
        XCTAssertNil(viewModel.runtimeStackReadError)
        XCTAssertEqual(viewModel.runtimeServiceResources.map(\.service), ["app"])
        XCTAssertEqual(
            viewModel.runtimeServiceResourceReadIssues,
            [RuntimeGuestServiceResourceReadIssue(service: "worker", message: "resource owner unavailable")]
        )
    }

    func testRuntimeStackRefreshPreservesStackReadFailureAndClearsResources() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.runtimeStackError = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "runtime stack unavailable"]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.runtimeServiceResources = [runtimeServiceResource(service: "stale")]

        await viewModel.refreshRuntimeStack()

        XCTAssertNil(viewModel.runtimeStackStatus)
        XCTAssertEqual(viewModel.runtimeStackReadError, "runtime stack unavailable")
        XCTAssertEqual(viewModel.runtimeServiceResources, [])
        XCTAssertEqual(viewModel.runtimeServiceResourceReadIssues, [])
    }

    func testRuntimeStackRefreshReplacesInitialReadFailureAfterGuestBecomesReady() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.runtimeStackError = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "guest address is unavailable: missing-vm-ip"]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshRuntimeStack()
        XCTAssertEqual(viewModel.runtimeStackReadError, "guest address is unavailable: missing-vm-ip")

        client.runtimeStackError = nil
        await viewModel.refreshRuntimeStack()

        XCTAssertEqual(client.runtimeStackStatusCount, 2)
        XCTAssertEqual(viewModel.runtimeStackStatus, client.runtimeStackStatus)
        XCTAssertNil(viewModel.runtimeStackReadError)
    }

    func testRestrictedClientPreventsLocalOnlyOperations() async {
        let client = FakeRuntimeClient(capabilities: .restricted)
        let nativeShell = FakeRuntimeNativeShell()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )
        viewModel.selectedBundleURL = URL(fileURLWithPath: "/bundle")
        viewModel.selectedBundleVerified = true
        viewModel.selectedBackupPath = "/backup"
        viewModel.selectedRuntimeDataBackupPath = "/runtime-data-backup"

        viewModel.chooseVitalFilesDirectory()
        await viewModel.chooseUpdateBundle()
        await viewModel.applySettings()
        await viewModel.verifySelectedBundle()
        await viewModel.applySelectedBundle()
        await viewModel.rollbackRuntime()
        await viewModel.deleteSelectedBackup()
        await viewModel.repairProxyPort()
        await viewModel.repairDatastore()
        await viewModel.repairVMDisk()
        await viewModel.repairRuntimeServices()
        await viewModel.createRedisBackup()
        await viewModel.importRedisBackup()
        await viewModel.restoreRedisBackup()
        await viewModel.createRuntimeDataBackup()
        await viewModel.restoreRuntimeDataBackup()
        await viewModel.deleteSelectedRuntimeDataBackup()
        await viewModel.exportLogs()
        viewModel.openLogs()
        viewModel.openBackups()
        viewModel.openRedisBackups()
        viewModel.openRuntimeDataBackups()
        viewModel.openVitalFilesDirectory()

        XCTAssertEqual(client.applySettingsCount, 0)
        XCTAssertEqual(client.verifyUpdateBundleCount, 0)
        XCTAssertEqual(client.applyUpdateBundleCount, 0)
        XCTAssertEqual(client.rollbackRuntimeCount, 0)
        XCTAssertEqual(client.deleteBackupCount, 0)
        XCTAssertEqual(client.repairProxyCount, 0)
        XCTAssertEqual(client.repairDatastoreCount, 0)
        XCTAssertEqual(client.repairVMDiskCount, 0)
        XCTAssertEqual(client.repairRuntimeServicesCount, 0)
        XCTAssertEqual(client.createRedisBackupCount, 0)
        XCTAssertEqual(client.restoreRedisBackupCount, 0)
        XCTAssertEqual(client.createRuntimeDataBackupCount, 0)
        XCTAssertEqual(client.restoreRuntimeDataBackupCount, 0)
        XCTAssertEqual(client.exportLogsCount, 0)
        XCTAssertEqual(client.preferredLogsPathCount, 0)
        XCTAssertEqual(nativeShell.createdDirectoryURLs, [])
        XCTAssertEqual(nativeShell.chooseDirectoryCount, 0)
        XCTAssertEqual(nativeShell.chooseUpdateBundleCount, 0)
        XCTAssertEqual(nativeShell.chooseRedisBackupArchiveCount, 0)
        XCTAssertEqual(nativeShell.chooseLogExportDestinationCount, 0)
        XCTAssertEqual(nativeShell.openedFileURLs, [])
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.actionUnavailable)
    }

    func testRepairProxyDoesNotRequirePresentationProxyPortFallback() async {
        let controlClient = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let hostClient = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        controlClient.status = platformState(proxyPort: nil)
        let viewModel = RuntimeViewModel(
            controlClient: controlClient,
            hostClient: hostClient,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: FakeRuntimeNativeShell()
        )

        await viewModel.repairProxyPort()

        XCTAssertEqual(controlClient.repairProxyCount, 0)
        XCTAssertEqual(hostClient.repairProxyCount, 1)
        XCTAssertNotEqual(viewModel.message, RuntimeHTTPStatusText.missingProxyPort)
    }

    func testRefreshSkipsReleaseMetadataWhenCapabilityIsUnavailable() async {
        var capabilities = RuntimeControlCapabilities.restricted
        capabilities.canStreamLogs = false
        let client = FakeRuntimeClient(capabilities: capabilities)
        let viewModel = RuntimeViewModel(controlClient: client, hostClient: client, healthNotifications: NoopHealthNotifications())
        viewModel.logStreaming = false
        client.loadStatusCount = 0

        await viewModel.refresh()

        XCTAssertEqual(client.loadReleaseInfoCount, 0)
        XCTAssertEqual(client.loadStatusCount, 1)
        XCTAssertEqual(client.loadBackupsCount, 1)
        XCTAssertEqual(viewModel.releaseInfo, .generated)
        XCTAssertNil(viewModel.releaseInfoErrorMessage)
    }

    func testRefreshPreservesReleaseMetadataReadFailureInsteadOfSilentGeneratedFallback() async {
        var capabilities = RuntimeControlCapabilities()
        capabilities.canViewReleaseMetadata = true
        let client = FakeRuntimeClient(capabilities: capabilities)
        client.releaseInfoLoadError = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "release metadata denied"]
        )
        let viewModel = RuntimeViewModel(controlClient: client, hostClient: client, healthNotifications: NoopHealthNotifications())
        viewModel.logStreaming = false

        await viewModel.refresh()

        XCTAssertEqual(client.loadReleaseInfoCount, 1)
        XCTAssertEqual(viewModel.releaseInfo, .generated)
        XCTAssertEqual(
            viewModel.releaseInfoErrorMessage,
            AppConstants.StatusText.releaseMetadataLoadFailed("release metadata denied")
        )
    }

    func testBackupRefreshFailurePreservesLastKnownBackupListAndSelection() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.backupsToLoad = [RuntimeBackup(path: "/backups/20260608-before-0.1.12", sizeBytes: 1024)]
        let viewModel = RuntimeViewModel(controlClient: client, hostClient: client, healthNotifications: NoopHealthNotifications())

        await viewModel.refreshBackupList()
        XCTAssertEqual(viewModel.backups.map(\.path), ["/backups/20260608-before-0.1.12"])
        XCTAssertEqual(viewModel.selectedBackupPath, "/backups/20260608-before-0.1.12")

        client.backupLoadError = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "backup directory denied"]
        )

        await viewModel.refreshBackupList()

        XCTAssertEqual(viewModel.backups.map(\.path), ["/backups/20260608-before-0.1.12"])
        XCTAssertEqual(viewModel.selectedBackupPath, "/backups/20260608-before-0.1.12")
        XCTAssertEqual(
            viewModel.backupListErrorMessage,
            AppConstants.StatusText.backupListLoadFailed("backup directory denied")
        )
    }

    func testRuntimeDataBackupRefreshSelectsExplicitRuntimeDataBackup() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.runtimeDataBackupsToLoad = [
            RuntimeBackup(path: "/backups/vitalserver-helper/20260610T010101Z-manual", sizeBytes: 2048),
        ]
        let viewModel = RuntimeViewModel(controlClient: client, hostClient: client, healthNotifications: NoopHealthNotifications())

        await viewModel.refreshBackupList()

        XCTAssertEqual(viewModel.runtimeDataBackups.map(\.path), ["/backups/vitalserver-helper/20260610T010101Z-manual"])
        XCTAssertEqual(viewModel.selectedRuntimeDataBackupPath, "/backups/vitalserver-helper/20260610T010101Z-manual")
        XCTAssertEqual(viewModel.selectedRuntimeDataBackup?.sizeBytes, 2048)
    }

    func testRuntimeDataBackupActionsCallExplicitPorts() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.runtimeDataBackupsToLoad = [
            RuntimeBackup(path: "/platform/backups/runtime-data/vitalserver-helper/selected", sizeBytes: nil)
        ]
        let viewModel = RuntimeViewModel(controlClient: client, hostClient: client, healthNotifications: NoopHealthNotifications())
        viewModel.runtimeDataBackups = [
            RuntimeBackup(path: "/platform/backups/runtime-data/vitalserver-helper/selected", sizeBytes: nil)
        ]
        viewModel.selectedRuntimeDataBackupPath = "/platform/backups/runtime-data/vitalserver-helper/selected"

        await viewModel.createRuntimeDataBackup()
        await viewModel.restoreRuntimeDataBackup()
        await viewModel.deleteSelectedRuntimeDataBackup()

        XCTAssertEqual(client.createRuntimeDataBackupCount, 1)
        XCTAssertEqual(client.restoreRuntimeDataBackupCount, 1)
        XCTAssertEqual(client.deleteBackupCount, 1)
        XCTAssertEqual(client.restoredRuntimeDataBackupURLs, [
            URL(fileURLWithPath: "/platform/backups/runtime-data/vitalserver-helper/selected")
        ])
        XCTAssertEqual(client.deletedBackupURLs, [
            URL(fileURLWithPath: "/platform/backups/runtime-data/vitalserver-helper/selected")
        ])
    }

    func testNativeShellProvidesDirectorySelectionWithoutLeakingPanelDetailsToController() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.directoryURL = URL(fileURLWithPath: "/Users/test/Vital Files")
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        viewModel.chooseVitalFilesDirectory()

        XCTAssertEqual(nativeShell.chooseDirectoryPrompts, [AppConstants.Actions.chooseDirectory])
        XCTAssertEqual(nativeShell.createdDirectoryURLs, [URL(fileURLWithPath: "/Users/test/Vital Files")])
        XCTAssertEqual(viewModel.settings.vitalFilesDirectory, "/Users/test/Vital Files")
    }

    func testProtectedVitalFilesDirectorySelectionIsRejected() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.directoryURL = URL(fileURLWithPath: "/Users/test/Desktop/Vital Files")
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )
        let previousDirectory = viewModel.settings.vitalFilesDirectory

        viewModel.chooseVitalFilesDirectory()

        XCTAssertEqual(nativeShell.chooseDirectoryPrompts, [AppConstants.Actions.chooseDirectory])
        XCTAssertEqual(nativeShell.createdDirectoryURLs, [])
        XCTAssertEqual(viewModel.settings.vitalFilesDirectory, previousDirectory)
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.vitalFilesDirectoryProtected)
    }

    func testAdvertisedURLInitialValuesFollowHostProxyPortWithoutClearingExplicitServiceURLs() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var initialSettings = RuntimeSettings()
        initialSettings.proxyPort = 8080
        initialSettings.vitalServerURL = RuntimeSettingsInitialValues.vitalServerURL(proxyPort: 8080)
        initialSettings.remoteConsoleURL = RuntimeSettingsInitialValues.remoteConsoleURL()
        initialSettings.publicHost = ""
        initialSettings.publicPort = 8080
        client.settings = initialSettings
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        viewModel.settings.proxyPort = 18080
        viewModel.syncAdvertisedURLWithProxyIfNeeded()

        XCTAssertEqual(viewModel.settings.publicHost, "")
        XCTAssertEqual(viewModel.settings.publicPort, 18080)
        XCTAssertEqual(viewModel.settings.vitalServerURL, "http://127.0.0.1:18080/")
        XCTAssertEqual(viewModel.settings.remoteConsoleURL, "http://127.0.0.1:18321/")

        viewModel.settings.vitalServerURL = "https://vitaldb.tirosh.ai/"
        viewModel.settings.remoteConsoleURL = "https://console.tirosh.ai/"
        viewModel.settings.proxyPort = 8080
        viewModel.syncAdvertisedURLWithProxyIfNeeded()

        XCTAssertEqual(viewModel.settings.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(viewModel.settings.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(viewModel.settings.publicHost, "")
        XCTAssertEqual(viewModel.settings.publicPort, 8080)
    }

    func testApplySettingsUsesAdvertisedServiceURLInitialValues() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(viewModel.settings.vitalServerURL, "http://127.0.0.1:80/")
        XCTAssertEqual(viewModel.settings.remoteConsoleURL, "http://127.0.0.1:18321/")

        XCTAssertTrue(viewModel.prepareApplySettings())
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.ready)
        XCTAssertNil(viewModel.settingsValidationMessage)
        XCTAssertEqual(viewModel.settings.vitalServerURL, "http://127.0.0.1:80/")
    }

    func testApplySettingsDoesNotSendAppliedVMSettingsSnapshot() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var installedSettings = RuntimeSettings()
        installedSettings.vitalFilesDirectory = "/saved/vital-files"
        installedSettings.appliedVMSettings = RuntimeAppliedVMSettings(
            cpuCount: 4,
            memoryGiB: 4,
            networkMode: .shared,
            bridgedInterface: nil,
            vitalFilesDirectory: "/applied/vital-files"
        )
        client.settings = installedSettings
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.applySettings()

        XCTAssertNil(client.lastAppliedSettings?.appliedVMSettings)
        XCTAssertEqual(client.lastAppliedSettings?.vitalFilesDirectory, "/saved/vital-files")
    }

    func testViewModelLoadsAdvertisedServiceURLInitialValuesFromEmptyInstalledSettings() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var installedSettings = RuntimeSettings()
        installedSettings.proxyPort = 18080
        installedSettings.runtimeControlPort = 18322
        installedSettings.vitalServerURL = ""
        installedSettings.remoteConsoleURL = ""
        client.settings = installedSettings

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(viewModel.settings.vitalServerURL, "http://127.0.0.1:18080/")
        XCTAssertEqual(viewModel.settings.remoteConsoleURL, "http://127.0.0.1:18322/")
    }

    func testRefreshKeepsAdvertisedServiceURLInitialValuesFromEmptyInstalledSettings() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var installedSettings = RuntimeSettings()
        installedSettings.proxyPort = 18080
        installedSettings.runtimeControlPort = 18322
        installedSettings.vitalServerURL = ""
        installedSettings.remoteConsoleURL = ""
        client.settings = installedSettings
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.settings.vitalServerURL = "stale-draft"
        viewModel.settings.remoteConsoleURL = "stale-draft"

        await viewModel.refresh()

        XCTAssertEqual(viewModel.settings.vitalServerURL, "http://127.0.0.1:18080/")
        XCTAssertEqual(viewModel.settings.remoteConsoleURL, "http://127.0.0.1:18322/")
    }

    func testStatusRefreshUsesRuntimeSettingsInsteadOfDraftSettings() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var installedSettings = RuntimeSettings()
        installedSettings.vitalFilesDirectory = "/applied/vital-files"
        client.settings = installedSettings
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.settings.vitalFilesDirectory = "/draft/vital-files"

        await viewModel.refreshHealthStatus()

        XCTAssertEqual(client.lastLoadHealthStatusSettings?.vitalFilesDirectory, "/applied/vital-files")
        XCTAssertEqual(viewModel.runtimeSettings.vitalFilesDirectory, "/applied/vital-files")
        XCTAssertEqual(viewModel.settings.vitalFilesDirectory, "/draft/vital-files")
    }

    func testStatusUsesAppliedVMSettingsUntilSavedSettingsAreRestarted() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var installedSettings = RuntimeSettings()
        installedSettings.cpuCount = 8
        installedSettings.memoryGiB = 8
        installedSettings.vitalFilesDirectory = "/saved/vital-files"
        installedSettings.appliedVMSettings = RuntimeAppliedVMSettings(
            cpuCount: 4,
            memoryGiB: 4,
            networkMode: .shared,
            bridgedInterface: nil,
            vitalFilesDirectory: "/applied/vital-files"
        )
        client.settings = installedSettings

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(viewModel.settings.vitalFilesDirectory, "/saved/vital-files")
        XCTAssertEqual(viewModel.runtimeSettings.vitalFilesDirectory, "/applied/vital-files")
        XCTAssertEqual(client.lastLoadStatusSettings?.vitalFilesDirectory, "/applied/vital-files")

        client.loadStatusCount = 0
        await viewModel.refreshHealthStatus()

        XCTAssertEqual(client.lastLoadHealthStatusSettings?.vitalFilesDirectory, "/applied/vital-files")
    }

    func testSavedSettingsStayDistinctFromDraftSettingsForRestartActions() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var installedSettings = RuntimeSettings()
        installedSettings.vitalFilesDirectory = "/saved/vital-files"
        installedSettings.appliedVMSettings = RuntimeAppliedVMSettings(
            cpuCount: 4,
            memoryGiB: 4,
            networkMode: .shared,
            bridgedInterface: nil,
            vitalFilesDirectory: "/applied/vital-files"
        )
        client.settings = installedSettings
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        viewModel.settings.vitalFilesDirectory = "/draft/vital-files"

        XCTAssertEqual(viewModel.savedSettings.vitalFilesDirectory, "/saved/vital-files")
        XCTAssertEqual(viewModel.settings.vitalFilesDirectory, "/draft/vital-files")
        XCTAssertEqual(viewModel.runtimeSettings.vitalFilesDirectory, "/applied/vital-files")
    }

    func testRestartVMRuntimeFromSettingsActivatesSavedSettingsThroughConfigureWorkflow() async {
        let controlClient = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let hostClient = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var savedSettings = RuntimeSettings()
        savedSettings.memoryGiB = 12
        savedSettings.vitalFilesDirectory = "/saved/vital-files"
        controlClient.settings = savedSettings
        let viewModel = RuntimeViewModel(
            controlClient: controlClient,
            hostClient: hostClient,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.restartVMRuntimeFromSettings()

        XCTAssertEqual(controlClient.repairRuntimeServicesCount, 0)
        XCTAssertEqual(hostClient.repairRuntimeServicesCount, 0)
        XCTAssertEqual(controlClient.applySettingsCount, 0)
        XCTAssertEqual(controlClient.restartVMRuntimeCount, 1)
        XCTAssertEqual(controlClient.lastAppliedSettings?.memoryGiB, 12)
        XCTAssertEqual(controlClient.lastAppliedSettings?.vitalFilesDirectory, "/saved/vital-files")
        XCTAssertEqual(controlClient.lastAppliedSettings?.restartAfterSave, false)
        XCTAssertEqual(controlClient.loadHealthStatusCount, 0)
        XCTAssertGreaterThanOrEqual(controlClient.loadStatusCount, 2)
    }

    func testOpenVitalFilesDirectoryUsesRuntimeSettingsInsteadOfDraftSettings() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var installedSettings = RuntimeSettings()
        installedSettings.vitalFilesDirectory = "/applied/vital-files"
        client.settings = installedSettings
        let nativeShell = FakeRuntimeNativeShell()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )
        viewModel.settings.vitalFilesDirectory = "/draft/vital-files"

        viewModel.openVitalFilesDirectory()

        XCTAssertEqual(nativeShell.openedFileURLs.map(\.path), ["/applied/vital-files"])
    }

    func testApplySettingsRejectsExplicitEmptyAdvertisedServiceURLs() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.settings.vitalServerURL = ""
        viewModel.settings.remoteConsoleURL = ""

        XCTAssertFalse(viewModel.prepareApplySettings())
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.invalidAdvertisedURL)
        XCTAssertEqual(viewModel.settingsValidationMessage, AppConstants.StatusText.invalidAdvertisedURL)
        XCTAssertEqual(viewModel.settings.vitalServerURL, "")
    }

    func testApplySettingsNormalizesLegacyAdvertisedHostFieldsWithoutClearingServiceURLs() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var initialSettings = RuntimeSettings()
        initialSettings.proxyPort = 8080
        initialSettings.vitalServerURL = "https://vitaldb.tirosh.ai/"
        initialSettings.remoteConsoleURL = "https://console.tirosh.ai/"
        initialSettings.publicHost = "legacy.example.test"
        initialSettings.publicPort = 8443
        client.settings = initialSettings
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertTrue(viewModel.prepareApplySettings())

        XCTAssertEqual(viewModel.settings.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(viewModel.settings.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(viewModel.settings.publicHost, "")
        XCTAssertEqual(viewModel.settings.publicPort, 8080)
    }

    func testNativeShellProvidesUpdateBundleURLAndClientVerifiesSelectedBundle() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let bundleURL = URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")
        nativeShell.updateBundleURL = bundleURL
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.chooseUpdateBundle()

        XCTAssertEqual(nativeShell.chooseUpdateBundlePrompts, [AppConstants.Actions.chooseBundle])
        XCTAssertEqual(viewModel.selectedBundleURL, bundleURL)
        XCTAssertEqual(viewModel.selectedBundleSummary, "bundle: /tmp/update-bundle.tar.gz")
        XCTAssertEqual(client.verifiedBundleURLs, [bundleURL])
        XCTAssertTrue(viewModel.selectedBundleVerified)
    }

    func testOpenAndExportOperationsUseNativeShellBoundary() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let exportURL = URL(fileURLWithPath: "/tmp/vitalserver-logs.zip")
        nativeShell.logExportDestinationURL = exportURL
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        viewModel.openLogs()
        viewModel.openBackups()
        viewModel.openRedisBackups()
        viewModel.openRuntimeDataBackups()
        viewModel.openVitalServer()
        viewModel.openRuntimeControlPWA()
        viewModel.openVitalDBWebsite()
        await viewModel.exportLogs()

        XCTAssertEqual(nativeShell.openedFileURLs, [
            URL(fileURLWithPath: "/logs"),
            URL(fileURLWithPath: "/backups"),
            URL(fileURLWithPath: "/platform/backups/runtime-data/redis"),
            URL(fileURLWithPath: "/platform/backups/runtime-data/vitalserver-helper"),
        ])
        XCTAssertEqual(nativeShell.openedWebURLs, [
            URL(string: AppConstants.Product.runtimeControlPWAURL(
                port: RuntimeSettingsInitialValues.runtimeControlPort
            )),
            URL(string: AppConstants.Product.vitalDBURL),
        ])
        XCTAssertEqual(nativeShell.chooseLogExportDestinationPrompts, [AppConstants.Actions.exportLogs])
        XCTAssertEqual(client.exportLogDestinationURLs, [exportURL])
    }

    func testImportRuntimeDataBackupCopiesSelectedFolderIntoManagedRuntimeDataBackupRoot() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let sourceURL = URL(fileURLWithPath: "/external/20260614T043455Z-manual", isDirectory: true)
        let destinationURL = URL(fileURLWithPath: "/platform/backups/runtime-data/vitalserver-helper/20260614T043455Z-manual", isDirectory: true)
        nativeShell.directoryURL = sourceURL
        nativeShell.pathStates = [
            sourceURL.path: .directory,
            "/platform/backups/runtime-data/vitalserver-helper": .directory,
            destinationURL.path: .missing,
        ]
        client.runtimeDataBackupsToLoad = [
            RuntimeBackup(path: destinationURL.path, sizeBytes: 1024),
        ]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.importRuntimeDataBackup()

        XCTAssertEqual(nativeShell.chooseDirectoryPrompts, [AppConstants.Actions.importBackups])
        XCTAssertEqual(nativeShell.copiedDirectories.map { [$0.source.path, $0.destination.path] }, [
            [sourceURL.path, destinationURL.path],
        ])
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.runtimeDataBackupImported)
        XCTAssertEqual(viewModel.selectedRuntimeDataBackupPath, destinationURL.path)
        XCTAssertEqual(client.loadBackupsCount, 1)
    }

    func testImportRedisBackupCopiesSelectedArchiveIntoManagedRedisBackupRoot() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let sourceURL = URL(fileURLWithPath: "/external/redis-20260614T043455Z.tar.gz")
        let destinationURL = URL(fileURLWithPath: "/platform/backups/runtime-data/redis/redis-20260614T043455Z.tar.gz")
        nativeShell.redisBackupArchiveURL = sourceURL
        nativeShell.pathStates = [
            sourceURL.path: .file,
            "/platform/backups/runtime-data/redis": .directory,
            destinationURL.path: .missing,
        ]
        client.redisBackupsToLoad = [
            RuntimeBackup(path: destinationURL.path, sizeBytes: 1024),
        ]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.importRedisBackup()

        XCTAssertEqual(nativeShell.chooseRedisBackupArchivePrompts, [AppConstants.Actions.importBackups])
        XCTAssertEqual(nativeShell.copiedFiles.map { [$0.source.path, $0.destination.path] }, [
            [sourceURL.path, destinationURL.path],
        ])
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.redisBackupImported)
        XCTAssertEqual(viewModel.selectedRedisBackupPath, destinationURL.path)
        XCTAssertEqual(client.loadBackupsCount, 1)
    }

    func testImportRedisBackupRejectsExistingManagedDestination() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let sourceURL = URL(fileURLWithPath: "/external/redis-20260614T043455Z.tar.gz")
        nativeShell.redisBackupArchiveURL = sourceURL
        nativeShell.pathStates = [
            sourceURL.path: .file,
            "/platform/backups/runtime-data/redis": .directory,
            "/platform/backups/runtime-data/redis/redis-20260614T043455Z.tar.gz": .file,
        ]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.importRedisBackup()

        XCTAssertTrue(nativeShell.copiedFiles.isEmpty)
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.redisBackupImportDestinationExists)
    }

    func testRestoreRedisBackupUsesSelectedManagedRedisArchive() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let selectedURL = URL(fileURLWithPath: "/platform/backups/runtime-data/redis/redis-20260614T043455Z.tar.gz")
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: FakeRuntimeNativeShell()
        )
        viewModel.selectedRedisBackupPath = selectedURL.path

        await viewModel.restoreRedisBackup()

        XCTAssertEqual(client.restoredRedisBackupURLs, [selectedURL])
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.redisRestoreCompleted)
    }

    func testImportRuntimeDataBackupRejectsExistingManagedDestination() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let sourceURL = URL(fileURLWithPath: "/external/20260614T043455Z-manual", isDirectory: true)
        nativeShell.directoryURL = sourceURL
        nativeShell.pathStates = [
            sourceURL.path: .directory,
            "/platform/backups/runtime-data/vitalserver-helper": .directory,
            "/platform/backups/runtime-data/vitalserver-helper/20260614T043455Z-manual": .directory,
        ]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.importRuntimeDataBackup()

        XCTAssertTrue(nativeShell.copiedDirectories.isEmpty)
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.runtimeDataBackupImportDestinationExists)
    }

    func testExportLogsReportsCleanupIssueFromHostResult() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let exportURL = URL(fileURLWithPath: "/tmp/vitalserver-logs.zip")
        nativeShell.logExportDestinationURL = exportURL
        client.exportLogsResult = RuntimeLogExportResult(
            destination: exportURL,
            cleanupIssue: "staging cleanup failed path=/tmp/staging reason=cleanup denied"
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.exportLogs()

        XCTAssertEqual(client.exportLogDestinationURLs, [exportURL])
        XCTAssertTrue(viewModel.message.contains(AppConstants.StatusText.logExportCompleted))
        XCTAssertTrue(viewModel.message.contains(exportURL.path))
        XCTAssertTrue(viewModel.message.contains("staging cleanup failed path=/tmp/staging"))
    }

    func testExportLogsRejectsProtectedDestinationBeforeCommandRuns() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.logExportDestinationURL = URL(fileURLWithPath: "/Users/test/Desktop/vitalserver-logs.zip")
        nativeShell.logExportDestinationValidationMessages["/Users/test/Desktop/vitalserver-logs.zip"] =
            AppConstants.StatusText.logExportDestinationProtected
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.exportLogs()

        XCTAssertEqual(nativeShell.chooseLogExportDestinationPrompts, [AppConstants.Actions.exportLogs])
        XCTAssertEqual(client.exportLogsCount, 0)
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.logExportDestinationProtected)
    }

    func testOpenFolderPromptsToCreateMissingDirectoryBeforeOpening() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.existingDirectories = ["/logs"]
        nativeShell.confirmCreateDirectoryResponses = [true]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        viewModel.openBackups()

        XCTAssertEqual(nativeShell.confirmCreateDirectoryPaths, ["/backups"])
        XCTAssertEqual(nativeShell.createdDirectoryURLs, [URL(fileURLWithPath: "/backups")])
        XCTAssertEqual(nativeShell.openedFileURLs, [URL(fileURLWithPath: "/backups")])
    }

    func testOpenFolderStopsWhenMissingDirectoryCreationIsCancelled() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.existingDirectories = []
        nativeShell.confirmCreateDirectoryResponses = [false]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        viewModel.openFolder("/missing")

        XCTAssertEqual(nativeShell.confirmCreateDirectoryPaths, ["/missing"])
        XCTAssertTrue(nativeShell.createdDirectoryURLs.isEmpty)
        XCTAssertTrue(nativeShell.openedFileURLs.isEmpty)
    }

    func testOpenExternalURLReportsInvalidURL() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        viewModel.openExternalURL("vitaldb.tirosh.ai")

        XCTAssertEqual(viewModel.message, AppConstants.StatusText.invalidRuntimeURL)
        XCTAssertEqual(nativeShell.openedWebURLs, [])
    }

    func testViewModelCanUseSeparateControlAndHostClients() async {
        let controlClient = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let hostClient = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.directoryURL = URL(fileURLWithPath: "/Users/test/Vital Files")
        let viewModel = RuntimeViewModel(
            controlClient: controlClient,
            hostClient: hostClient,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )
        controlClient.loadStatusCount = 0

        viewModel.chooseVitalFilesDirectory()
        await viewModel.createRuntimeDataBackup()
        await viewModel.refresh()

        XCTAssertEqual(controlClient.loadStatusCount, 2)
        XCTAssertEqual(controlClient.createRuntimeDataBackupCount, 0)
        XCTAssertEqual(hostClient.createRuntimeDataBackupCount, 1)
        XCTAssertEqual(nativeShell.createdDirectoryURLs, [URL(fileURLWithPath: "/Users/test/Vital Files")])
        XCTAssertEqual(hostClient.loadBackupsCount, 2)
    }

    func testHealthRefreshDoesNotLoadHeavyObservationHistories() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshHealthStatus()

        XCTAssertEqual(client.loadHealthStatusCount, 1)
        XCTAssertEqual(client.loadRuntimeEventsCount, 0)
        XCTAssertEqual(client.loadVitalDBRecordersCount, 0)
    }

    func testHealthRefreshDoesNotPublishContainerObservationAsCurrentProductStatus() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.healthStatus = platformState(runtimeVersion: "health-refreshed")
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshHealthStatus()

        XCTAssertEqual(viewModel.status.installedVersion, "health-refreshed")
    }

    func testVitalRecorderRefreshUpdatesCurrentObservationSnapshot() async {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-06-01T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            anomalies: [
                VitalDBAnomalyObservation(
                    id: "duplicate-ip-1",
                    kind: .duplicateIP,
                    severity: .warning,
                    observedAt: "2026-06-01T00:00:00Z",
                    subject: "10.0.0.10",
                    message: "duplicate-ip"
                ),
            ]
        )
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.vitalDBObservation = observation
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshVitalRecorders()

        XCTAssertEqual(viewModel.vitalDBObservationSnapshot.observation, observation)
    }

    func testVitalRecorderRefreshUpdatesBedsFromDedicatedBedReadModel() async {
        let bed = RuntimeVitalBedRecord(
            bedID: "bed-postgres",
            name: "OR 1",
            vrcode: "VR_A",
            status: .online,
            patientConnected: true,
            firstSeenAt: "2026-07-01T00:00:00+00:00",
            lastSeenAt: "2026-07-01T00:01:00+00:00",
            observationCount: 1,
            currentAnomalyCount: 0,
            latestAnomalySeverity: nil
        )
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.vitalDBBedHistory = RuntimeVitalBedHistory(
            updatedAt: "2026-07-01T00:01:00+00:00",
            beds: [bed]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshVitalRecorders()

        XCTAssertEqual(client.loadVitalDBRecordersCount, 1)
        XCTAssertEqual(client.loadVitalDBBedsCount, 1)
        XCTAssertEqual(viewModel.vitalBeds.beds.map(\.bedID), ["bed-postgres"])
        XCTAssertTrue(viewModel.vitalRecorders.beds.isEmpty)
    }

    func testCancelledVitalRecorderRefreshDoesNotPublishItsResult() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.vitalRelationships = RuntimeVitalRelationshipHistory(
            readError: "previous relationship state"
        )

        let refresh = Task { @MainActor in
            await viewModel.refreshVitalRecorders()
        }
        refresh.cancel()
        await refresh.value

        XCTAssertEqual(
            viewModel.vitalRelationships.readError,
            "previous relationship state"
        )
    }

    func testVitalDBVisibilityActionsUseRuntimeControlClientAndUpdateReadModel() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.vitalDBVisibilityHistory = RuntimeVitalRecorderHistory(
            updatedAt: "2026-07-01T00:00:00+00:00"
        )
        client.vitalDBBedVisibilityHistory = RuntimeVitalBedHistory(
            updatedAt: "2026-07-01T00:00:00+00:00"
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        let hideSucceeded = await viewModel.hideVitalDBRecorder(vrcode: "VR_A")
        let unhideSucceeded = await viewModel.unhideVitalDBRecorder(vrcode: "VR_A")
        let deleteSucceeded = await viewModel.deleteVitalDBRecorder(vrcode: "VR_A")
        await viewModel.hideVitalDBBed(bedID: "bed-a")
        await viewModel.unhideVitalDBBed(bedID: "bed-a")
        await viewModel.deleteVitalDBBed(bedID: "bed-a")

        XCTAssertTrue(hideSucceeded)
        XCTAssertTrue(unhideSucceeded)
        XCTAssertTrue(deleteSucceeded)
        XCTAssertEqual(client.hiddenRecorderRequests, [.init(vrcodes: ["VR_A"])])
        XCTAssertEqual(client.unhiddenRecorderRequests, [.init(vrcodes: ["VR_A"])])
        XCTAssertEqual(client.deletedRecorderRequests, [.init(vrcodes: ["VR_A"])])
        XCTAssertEqual(client.hiddenBedRequests, [.init(bedIDs: ["bed-a"])])
        XCTAssertEqual(client.unhiddenBedRequests, [.init(bedIDs: ["bed-a"])])
        XCTAssertEqual(client.deletedBedRequests, [.init(bedIDs: ["bed-a"])])
        XCTAssertEqual(viewModel.vitalRecorders.updatedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(viewModel.vitalBeds.updatedAt, "2026-07-01T00:00:00+00:00")
        XCTAssertEqual(viewModel.vitalDBVisibilityActionMessage, "Hidden bed deleted.")
        XCTAssertFalse(viewModel.isRunningVitalDBVisibilityAction)
    }

    func testVitalDBRecorderVisibilityFailureDoesNotReportSuccess() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.vitalDBVisibilityError = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "visibility owner unavailable"]
        )
        let originalHistory = RuntimeVitalRecorderHistory(
            updatedAt: "2026-06-30T00:00:00+00:00"
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.vitalRecorders = originalHistory

        let succeeded = await viewModel.hideVitalDBRecorder(vrcode: "VR_A")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.vitalRecorders, originalHistory)
        XCTAssertEqual(
            viewModel.vitalDBVisibilityActionMessage,
            "visibility owner unavailable"
        )
        XCTAssertFalse(viewModel.isRunningVitalDBVisibilityAction)
    }

    func testRuntimeEventRefreshUsesSelectedPeriodAndType() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.runtimeEventPeriod = RuntimeEventPeriodOption.lastHour.rawValue
        viewModel.runtimeEventFilter = RuntimeEventType.watchdogSkipped.rawValue

        await viewModel.refreshRuntimeEvents()

        XCTAssertEqual(client.runtimeEventQueries.count, 2)
        XCTAssertEqual(client.runtimeEventQueries.first?.limit, 50)
        XCTAssertEqual(client.runtimeEventQueries.first?.eventType, .watchdogSkipped)
        XCTAssertNotNil(client.runtimeEventQueries.first?.since)
        XCTAssertEqual(client.runtimeEventQueries.last?.limit, 1)
        XCTAssertNil(client.runtimeEventQueries.last?.eventType)
        XCTAssertNotNil(client.runtimeEventQueries.last?.since)
    }

    func testProductLabScenarioRefreshSelectsFirstScenario() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labScenariosToLoad = RuntimeLabScenarioList(
            state: .loaded,
            scenarios: [
                RuntimeLabScenario(scenarioId: "case-a", name: "Case A", category: "generated"),
                RuntimeLabScenario(scenarioId: "case-b", name: "Case B", category: "generated"),
            ]
        )
        client.labVitalFilesToLoad = RuntimeLabVitalFileList(
            state: .loaded,
            vitalFiles: [
                RuntimeLabVitalFile(
                    displayName: "case.vital",
                    relativePath: "MORA04/case.vital",
                    guestPath: "/mnt/tirosh-vital-files/MORA04/case.vital",
                    sizeBytes: 123
                )
            ]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshProductLabScenarios()

        XCTAssertEqual(viewModel.labScenarios.scenarios.count, 2)
        XCTAssertEqual(viewModel.selectedLabScenarioID, "case-a")
        XCTAssertEqual(viewModel.selectedLabVitalFileRelativePath, "MORA04/case.vital")
        XCTAssertEqual(viewModel.labActionMessage, RuntimeLabPanelText.loadedLabScenarios(2))
    }

    func testProductLabCreateSessionUsesRuntimeControlClient() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.selectedLabScenarioID = "case-a"
        viewModel.labSessionName = "Morning run"
        viewModel.labRecorderCount = 3

        await viewModel.createProductLabSession()

        XCTAssertEqual(client.labCreateRequests, [
            RuntimeLabSessionCreateRequest(
                scenarioId: "case-a",
                name: "Morning run",
                recorderCount: 3,
                targetURL: "http://edge/"
            )
        ])
        XCTAssertEqual(viewModel.selectedLabSessionID, "lab-session-1")
        XCTAssertEqual(viewModel.labActionMessage, RuntimeLabPanelText.createdLabSession("lab-session-1"))
    }

    func testProductLabCreateSessionCanTargetExistingLabBeds() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.selectedLabScenarioID = "case-a"
        viewModel.labSessionName = "Target existing beds"
        viewModel.labRecorderCount = 5
        viewModel.labSessionBedIDs = "manual_session_1-bed-1, manual_session_1-bed-2"

        await viewModel.createProductLabSession()

        XCTAssertEqual(client.labCreateRequests, [
            RuntimeLabSessionCreateRequest(
                scenarioId: "case-a",
                name: "Target existing beds",
                recorderCount: 2,
                targetURL: "http://edge/",
                bedIds: ["manual_session_1-bed-1", "manual_session_1-bed-2"]
            )
        ])
    }

    func testProductLabRefreshSelectsPersistedRunningSessionAndItsRecorders() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labSessionsToLoad = RuntimeLabSessionList(
            state: .loaded,
            sessions: [
                RuntimeLabSession(
                    sessionId: "stopped-session",
                    state: .stopped,
                    scenarioId: "case-a",
                    recorderCount: 1,
                    targetURL: "http://edge/"
                ),
                RuntimeLabSession(
                    sessionId: "running-session",
                    state: .running,
                    scenarioId: "case-b",
                    recorderCount: 1,
                    targetURL: "http://edge/"
                ),
            ]
        )
        client.labRecordersToLoad = RuntimeLabRecorderList(
            state: .loaded,
            recorders: [
                RuntimeLabRecorder(
                    recorderId: "running-recorder",
                    sessionId: "running-session",
                    bedId: "running-bed",
                    vrcode: "LAB-RUN001",
                    state: .running
                ),
                RuntimeLabRecorder(
                    recorderId: "other-recorder",
                    sessionId: "stopped-session",
                    bedId: "stopped-bed",
                    vrcode: "LAB-STOP01",
                    state: .stopped
                ),
            ]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshProductLabReadModels()

        XCTAssertEqual(viewModel.selectedLabSessionID, "running-session")
        XCTAssertEqual(viewModel.selectedLabSession?.state, .running)
        XCTAssertEqual(viewModel.selectedLabSessionRecorders.map(\.recorderId), ["running-recorder"])
        XCTAssertTrue(viewModel.labCanStopSelectedSession)
        XCTAssertFalse(viewModel.labCanStartSelectedSession)
    }

    func testProductLabSelectedSessionUsesNewerDetailStateThanSessionList() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labSessionsToLoad = RuntimeLabSessionList(
            state: .loaded,
            sessions: [
                RuntimeLabSession(
                    sessionId: "lab-session-1",
                    state: .accepted,
                    scenarioId: "case-a",
                    recorderCount: 1,
                    targetURL: "http://edge/"
                ),
            ]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshProductLabReadModels()

        XCTAssertEqual(viewModel.labSessions.sessions.first?.state, .accepted)
        XCTAssertEqual(viewModel.labSessionResponse.session?.state, .running)
        XCTAssertEqual(viewModel.selectedLabSession?.state, .running)
        XCTAssertTrue(viewModel.labCanStopSelectedSession)
        XCTAssertFalse(viewModel.labCanStartSelectedSession)
    }

    func testProductLabFailedSessionCanRetry() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.selectedLabSessionID = "failed-session"
        viewModel.labSessionResponse = RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: "failed-session",
                state: .failed,
                scenarioId: "vital-file-replay",
                recorderCount: 1,
                targetURL: "http://edge/",
                failure: RuntimeLabSessionFailure(
                    stage: .fileValidation,
                    code: .invalidWaveformSampleRate,
                    message: "invalid waveform sample rate",
                    failedAt: "2026-07-21T03:00:00Z"
                )
            )
        )

        XCTAssertTrue(viewModel.labCanStartSelectedSession)
        XCTAssertFalse(viewModel.labCanStopSelectedSession)
    }

    func testProductLabRecorderControlsUseExplicitRunningSessionOwnership() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labSessionsToLoad = RuntimeLabSessionList(
            state: .loaded,
            sessions: [
                RuntimeLabSession(
                    sessionId: "running-session",
                    state: .running,
                    scenarioId: "case-a",
                    recorderCount: 1,
                    targetURL: "http://edge/"
                ),
            ]
        )
        client.labRecordersToLoad = RuntimeLabRecorderList(
            state: .loaded,
            recorders: [
                RuntimeLabRecorder(
                    recorderId: "session-recorder",
                    sessionId: "running-session",
                    bedId: "session-bed",
                    vrcode: "LAB-REC001",
                    state: .running
                ),
                RuntimeLabRecorder(
                    recorderId: "foreign-recorder",
                    sessionId: "another-session",
                    bedId: "foreign-bed",
                    vrcode: "LAB-REC002",
                    state: .running
                ),
            ]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        await viewModel.refreshProductLabReadModels()

        await viewModel.stopProductLabRecorder("session-recorder")
        await viewModel.startProductLabRecorder("session-recorder")
        await viewModel.stopProductLabRecorder("foreign-recorder")

        XCTAssertEqual(client.labStoppedRecorderRequests, ["running-session/session-recorder"])
        XCTAssertEqual(client.labStartedRecorderRequests, ["running-session/session-recorder"])
        XCTAssertEqual(viewModel.labActionMessage, RuntimeLabPanelText.chooseSessionLabRecorder)
    }

    func testProductLabRunningRecorderCanStopWhenSessionStateIsAccepted() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labSessionsToLoad = RuntimeLabSessionList(
            state: .loaded,
            sessions: [
                RuntimeLabSession(
                    sessionId: "accepted-session",
                    state: .accepted,
                    scenarioId: "case-a",
                    recorderCount: 1,
                    targetURL: "http://edge/"
                ),
            ]
        )
        client.labRecordersToLoad = RuntimeLabRecorderList(
            state: .loaded,
            recorders: [
                RuntimeLabRecorder(
                    recorderId: "running-recorder",
                    sessionId: "accepted-session",
                    bedId: "session-bed",
                    vrcode: "LAB-REC001",
                    state: .running
                ),
            ]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        await viewModel.refreshProductLabReadModels()
        viewModel.labSessionResponse = RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: "accepted-session",
                state: .accepted,
                scenarioId: "case-a",
                recorderCount: 1,
                targetURL: "http://edge/"
            )
        )

        await viewModel.stopProductLabRecorder("running-recorder")

        XCTAssertEqual(
            client.labStoppedRecorderRequests,
            ["accepted-session/running-recorder"]
        )
    }

    func testProductLabVitalFileReplayUsesGuestMountedPath() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            initialSettings: RuntimeSettings(
                vitalFilesDirectory: "/Users/Shared/VitalServerHelper/vital-files"
            ),
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.selectedLabVitalFileRelativePath = "case.vital"
        viewModel.labSessionName = "Replay run"

        await viewModel.replayVitalFileWithProductLab()

        XCTAssertEqual(client.labReplayRequests, [
            RuntimeLabVitalFileReplayRequest(
                vitalFileRelativePath: "case.vital",
                sessionName: "Replay run",
                targetURL: "http://edge/",
                resourceSelection: RuntimeLabVitalFileReplayResourceSelection(mode: .quickCreate),
                repeatPolicy: RuntimeLabVitalFileReplayPolicy(mode: .once)
            )
        ])
        XCTAssertEqual(client.labStartedSessionIDs, ["lab-replay-1"])
        XCTAssertEqual(client.loadVitalDBRecordersCount, 1)
        XCTAssertEqual(viewModel.selectedLabSessionID, "lab-replay-1")
    }

    func testProductLabVitalFileUploadImportsSelectedHostFilesIntoLibrary() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labVitalFilesToLoad = RuntimeLabVitalFileList(
            state: .loaded,
            vitalFiles: [
                RuntimeLabVitalFile(
                    displayName: "case.vital",
                    relativePath: "case.vital",
                    guestPath: "/mnt/tirosh-vital-files/case.vital",
                    sizeBytes: 42
                )
            ]
        )
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.vitalFileUploadSources = [
            RuntimeLabVitalFileUploadSource(
                fileName: "case.vital",
                content: Data("case".utf8)
            )
        ]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            initialSettings: RuntimeSettings(
                vitalFilesDirectory: "/Users/Shared/VitalServerHelper/vital-files"
            ),
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )
        viewModel.labVitalFileUploadSources = [URL(fileURLWithPath: "/tmp/case.vital")]

        await viewModel.uploadVitalFileToProductLab()

        XCTAssertEqual(nativeShell.readVitalFileSources, [[URL(fileURLWithPath: "/tmp/case.vital")]])
        XCTAssertEqual(client.labUploadRequests.map { $0.map(\.fileName) }, [["case.vital"]])
        XCTAssertEqual(viewModel.labVitalFileImportMessage, RuntimeLabPanelText.uploadedLabVitalFiles(1))
        XCTAssertEqual(viewModel.labVitalFiles.vitalFiles.map(\.relativePath), ["case.vital"])
        XCTAssertEqual(viewModel.selectedLabVitalFileRelativePath, "case.vital")
    }

    func testProductLabVitalFileUploadShowsOnlyFailedFilesForPartialBatch() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labUploadResponse = RuntimeLabVitalFileLibraryUploadResponse(
            state: .partial,
            files: [
                RuntimeLabVitalFileLibraryUploadItem(
                    fileName: "valid.vital",
                    relativePath: "valid.vital",
                    sizeBytes: 5
                )
            ],
            failedFiles: [
                RuntimeLabVitalFileLibraryUploadFailure(
                    fileName: "broken.vital",
                    reason: "Vital file gzip stream is invalid."
                )
            ]
        )
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.vitalFileUploadSources = [
            RuntimeLabVitalFileUploadSource(fileName: "valid.vital", content: Data()),
            RuntimeLabVitalFileUploadSource(fileName: "broken.vital", content: Data())
        ]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )
        viewModel.labVitalFileUploadSources = [
            URL(fileURLWithPath: "/tmp/valid.vital"),
            URL(fileURLWithPath: "/tmp/broken.vital")
        ]

        await viewModel.uploadVitalFileToProductLab()

        XCTAssertTrue(viewModel.labVitalFileImportFailed)
        XCTAssertEqual(
            viewModel.labVitalFileImportMessage,
            "broken.vital: Vital file gzip stream is invalid."
        )
        XCTAssertFalse(viewModel.labVitalFileImportMessage.contains("valid.vital"))
    }

    func testProductLabFinishUsesTerminalSessionCommand() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.labSessionsToLoad = RuntimeLabSessionList(
            state: .loaded,
            sessions: [
                RuntimeLabSession(
                    sessionId: "lab-session-1",
                    state: .running,
                    scenarioId: "case-a",
                    recorderCount: 1,
                    targetURL: "http://edge/"
                )
            ]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.selectedLabSessionID = "lab-session-1"
        await viewModel.refreshProductLabReadModels()

        XCTAssertTrue(viewModel.labCanFinishSelectedSession)
        await viewModel.finishProductLabSession()

        XCTAssertEqual(client.labFinishedSessionIDs, ["lab-session-1"])
    }

    func testSystemNativeShellReadsMultipleVitalFilesForUpload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = sources.appendingPathComponent("first.vital")
        let second = sources.appendingPathComponent("second.VITAL")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let uploadSources = try SystemRuntimeNativeShell().readVitalFileUploadSources(
            [first, second]
        )

        XCTAssertEqual(uploadSources.map(\.fileName), ["first.vital", "second.VITAL"])
        XCTAssertEqual(uploadSources, [
            RuntimeLabVitalFileUploadSource(
                fileName: "first.vital",
                fileURL: first,
                sizeBytes: 5,
                accessMode: .securityScoped
            ),
            RuntimeLabVitalFileUploadSource(
                fileName: "second.VITAL",
                fileURL: second,
                sizeBytes: 6,
                accessMode: .securityScoped
            ),
        ])
    }

    func testSystemNativeShellForwardsEachReadableFileForOwnerSideBatchValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = firstDirectory.appendingPathComponent("valid.vital")
        let invalid = secondDirectory.appendingPathComponent("invalid.txt")
        let duplicateName = secondDirectory.appendingPathComponent("valid.vital")
        try Data("valid".utf8).write(to: valid)
        try Data("invalid".utf8).write(to: invalid)
        try Data("duplicate".utf8).write(to: duplicateName)

        let uploadSources = try SystemRuntimeNativeShell().readVitalFileUploadSources(
            [valid, invalid, duplicateName]
        )

        XCTAssertEqual(
            uploadSources.map(\.fileName),
            ["valid.vital", "invalid.txt", "valid.vital"]
        )
    }

    func testProductLabBedAndRecorderManagementUseRuntimeControlClient() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.createProductLabBeds()
        await viewModel.createProductLabRecorderForSelectedBed()
        await viewModel.deleteSelectedProductLabRecorder()
        await viewModel.deleteSelectedProductLabBed()

        XCTAssertEqual(client.labCreateBedRequests, [
            RuntimeLabBedCreateRequest(
                count: 1,
                prefix: "Lab bed",
                targetURL: "http://edge/"
            )
        ])
        XCTAssertEqual(client.labCreateRecorderRequests, [
            RuntimeLabRecorderCreateRequest(bedIds: ["lab-session-1-bed-1"])
        ])
        XCTAssertEqual(client.labDeleteRecorderRequests, [
            RuntimeLabRecorderDeleteRequest(recorderIds: ["lab-session-1-recorder-1"])
        ])
        XCTAssertEqual(client.labDeleteBedRequests, [
            RuntimeLabBedDeleteRequest(bedIds: ["lab-session-1-bed-1"])
        ])
    }

    func testProductLabCommandsAreBlockedWhenLabCapabilityIsUnavailable() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities(canUseLab: false))
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            initialSettings: RuntimeSettings(
                vitalFilesDirectory: "/Users/Shared/VitalServerHelper/vital-files"
            ),
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.selectedLabScenarioID = "case-a"
        viewModel.labSessionName = "Morning run"
        viewModel.labRecorderCount = 3
        viewModel.selectedLabSessionID = "lab-session-1"
        viewModel.selectedLabVitalFileRelativePath = "case.vital"

        XCTAssertFalse(viewModel.labCanUseProductLab)
        XCTAssertFalse(viewModel.labCanCreateSession)
        XCTAssertFalse(viewModel.labCanControlSelectedSession)
        XCTAssertFalse(viewModel.labCanReplayVitalFile)

        await viewModel.createProductLabSession()
        await viewModel.startProductLabSession()
        await viewModel.stopProductLabSession()
        await viewModel.finishProductLabSession()
        await viewModel.replayVitalFileWithProductLab()

        XCTAssertEqual(client.labCreateRequests, [])
        XCTAssertEqual(client.labStartedSessionIDs, [])
        XCTAssertEqual(client.labStoppedSessionIDs, [])
        XCTAssertEqual(client.labFinishedSessionIDs, [])
        XCTAssertEqual(client.labReplayRequests, [])
        XCTAssertEqual(viewModel.labActionMessage, RuntimeLabPanelText.labCapabilityUnavailable)
        XCTAssertEqual(viewModel.labActionMessageTone, .failure)
    }

    func testRuntimePanelsRenderSmokeState() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        applySmokeState(to: viewModel)

        render(RuntimeStatusPanel(
            viewModel: viewModel,
            showingRecorderDetails: .constant(true),
            showingResourceUsage: .constant(true)
        ))
        render(RuntimeRecordersPanel(viewModel: viewModel))
        render(RuntimeBedsPanel(viewModel: viewModel))
        render(RuntimeObservabilityPanel(viewModel: viewModel))
        render(RuntimeLogPanel(viewModel: viewModel))
        render(RuntimeSettingsPanel(
            viewModel: viewModel,
            showingApplySettingsConfirmation: .constant(false),
            showingRestartVMRuntimeConfirmation: .constant(false)
        ))
        render(RuntimeUpdatePanel(viewModel: viewModel, showingUpdateConfirmation: .constant(false)))
        render(RuntimeInfoPanel(viewModel: viewModel))
        render(RuntimeDangerZonePanel(
            viewModel: viewModel,
            showingDeleteBackupConfirmation: .constant(false),
            showingDeleteRuntimeDataBackupConfirmation: .constant(false),
            showingUninstallConfirmation: .constant(false),
            showingCleanUninstallConfirmation: .constant(false)
        ))
        render(RuntimeAdvancedPanel(
            viewModel: viewModel,
            showingApplySettingsConfirmation: .constant(false),
            showingRollbackConfirmation: .constant(false),
            showingRestoreRuntimeDataBackupConfirmation: .constant(false),
            showingRestoreRedisBackupConfirmation: .constant(false),
            showingRepairProxyConfirmation: .constant(false),
            showingRepairDatastoreConfirmation: .constant(false),
            showingRepairVMDiskConfirmation: .constant(false),
            showingRepairRuntimeServicesConfirmation: .constant(false),
            hoveredServiceLink: Binding<String?>(get: { nil }, set: { _ in }),
            showingRecoveryOperations: true,
            showingAdvancedRepairTools: true,
            showingNetworkOverrides: true,
            showingAdminOperations: true
        ))
        render(RuntimeLabPanel(viewModel: viewModel))
        render(ContentView().environmentObject(viewModel))
    }

    func testRecordersPanelLeavesVerticalScrollingToSectionContainer() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        applySmokeState(to: viewModel)
        let host = NSHostingView(rootView: ScrollView(.vertical) {
            RuntimeRecordersPanel(viewModel: viewModel)
        })
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 500)
        host.layoutSubtreeIfNeeded()

        let verticalScrollViews = descendantScrollViews(in: host)
            .filter(\.hasVerticalScroller)

        XCTAssertEqual(verticalScrollViews.count, 1)
    }

    func testRecorderActivityPollingRefreshesUntilCancelled() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        let query = RuntimeVitalRecorderActivityWindowQuery(
            vrcode: "06311eba",
            bucketSeconds: 60,
            period: .lastHour,
            pageIndex: nil
        )
        let pollingTask = Task {
            await viewModel.pollVitalRecorderActivityWindow(
                query: query,
                intervalNanoseconds: 1_000_000
            )
        }

        for _ in 0..<100 where client.loadVitalDBRecorderActivityWindowCount < 2 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        pollingTask.cancel()
        await pollingTask.value

        XCTAssertGreaterThanOrEqual(client.loadVitalDBRecorderActivityWindowCount, 2)
        XCTAssertEqual(client.vitalDBRecorderActivityQueries.last, query)
    }

    func testRecorderVitalFilesLoadOnlyWhenExplicitlyRequested() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadVitalDBRecorderVitalFilesCount, 0)
        await viewModel.refreshVitalRecorderVitalFiles(vrcode: "06311eba")

        XCTAssertEqual(client.loadVitalDBRecorderVitalFilesCount, 1)
        XCTAssertEqual(client.vitalDBRecorderVitalFileVrcodes, ["06311eba"])
        XCTAssertEqual(
            viewModel.recorderVitalFileHistories["06311eba"]?.vrcode,
            "06311eba"
        )
    }

    func testRecorderObservabilityDetailLoadsOnlyWhenExplicitlyRequested() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadRecorderObservabilityDetailCount, 0)
        await viewModel.refreshRecorderObservabilityDetail(vrcode: "06311eba")

        XCTAssertEqual(client.loadRecorderObservabilityDetailCount, 1)
        XCTAssertEqual(client.recorderObservabilityDetailVrcodes, ["06311eba"])
        XCTAssertEqual(
            viewModel.recorderObservabilityDetails["06311eba"]?.vrcode,
            "06311eba"
        )
    }

    func testRuntimeControlRecoveryRelaunchesHelperForFreshLocalSession() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        viewModel.reconnectRuntimeControl()

        XCTAssertEqual(nativeShell.relaunchHelperCount, 1)
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.runtimeControlReconnecting)
    }

    func testRuntimeSettingsPanelRendersOutOfRangeSliderSettings() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.settings.cpuCount = 1
        viewModel.settings.memoryGiB = 0
        viewModel.settings.diskGiB = 1
        viewModel.settings.recorderIngressSendDataReplayMaxMiBPerSecond = 0
        viewModel.settings.backupRetentionCount = 0
        viewModel.settings.logArchiveRetentionDays = 0
        viewModel.settings.logArchiveMaximumGiB = 999
        viewModel.settings.vitalServerContainerMemoryLimitMiB = 64
        viewModel.settings.recorderIngressContainerMemoryLimitMiB = 16
        viewModel.settings.redisContainerMemoryLimitMiB = 16

        render(RuntimeSettingsPanel(
            viewModel: viewModel,
            showingApplySettingsConfirmation: .constant(false),
            showingRestartVMRuntimeConfirmation: .constant(false)
        ))
    }

    private func applySmokeState(to viewModel: RuntimeViewModel) {
        let observedAt = "2026-05-30T00:00:00Z"
        let activity = VitalDBRecorderActivityObservation(
            windowSeconds: 60,
            messageCount: 120,
            byteCount: 4_096,
            roomCount: 2,
            firstSeenAt: observedAt,
            lastSeenAt: observedAt,
            messagesPerSecond: 2,
            bytesPerSecond: 68
        )
        let observation = VitalDBObservationDocument(
            observedAt: observedAt,
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "vr-001",
                    ip: "10.0.0.10",
                    lastSeenAt: observedAt,
                    version: "1.0",
                    info: "recorder",
                    config: "default",
                    online: true,
                    activity: activity
                )
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-001",
                    name: "OR-1",
                    vrcode: "vr-001",
                    lastSeenAt: observedAt,
                    patientConnected: true,
                    online: true
                )
            ],
            proxyConnections: [
                VitalDBProxyConnectionObservation(
                    observedAt: observedAt,
                    remoteAddress: "10.0.0.20",
                    requestURI: "/socket.io",
                    status: "101",
                    websocketHandshake: true
                )
            ],
            anomalies: [
                VitalDBAnomalyObservation(
                    id: "anomaly-001",
                    kind: .staleRecorder,
                    severity: .warning,
                    observedAt: observedAt,
                    subject: "vr-001",
                    message: "stale recorder"
                )
            ]
        )
        viewModel.status = platformState(
            runtimeInstallationState: .executable,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            sleepPreventionServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            runtimeVersion: "2026.05.30",
            latestBackup: "/backups/latest.tar.gz",
            vmState: .running,
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            hostProxyHTTP: "200",
            runtimeControlHTTP: "200",
            runtimeControlStartedAt: observedAt,
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            dataStorage: ResourceUsage(usedBytes: 20 * 1024 * 1024, totalBytes: 200 * 1024 * 1024),
            proxyPort: 8080
        )
        viewModel.vitalRecorders = RuntimeVitalRecorderHistory(observations: [observation])
        viewModel.vitalRelationships = RuntimeVitalRelationshipHistory(readError: "relationship projection delayed")
        viewModel.runtimeEvents = RuntimeEventHistory(events: [
            RuntimeEventDocument(
                id: "event-001",
                eventType: .statusChanged,
                timestamp: observedAt,
                product: "VitalServer",
                status: .healthy,
                previousStatus: .degraded,
                operation: .watchdog,
                message: "runtime recovered",
                runtimeVersion: "2026.05.30",
                failureReasons: [],
                vitalDBObservation: observation,
                progress: nil
            )
        ], matchingCount: 1)
        viewModel.runtimeEventsLast24HoursCount = 1
        viewModel.backups = [RuntimeBackup(path: "/backups/backup-001.tar.gz", sizeBytes: 1024)]
        viewModel.selectedBackupPath = "/backups/backup-001.tar.gz"
        viewModel.runtimeDataBackups = [RuntimeBackup(path: "/backups/vitalserver-helper/backup-001", sizeBytes: 2048)]
        viewModel.selectedRuntimeDataBackupPath = "/backups/vitalserver-helper/backup-001"
        viewModel.settings.vitalServerURL = "https://vitaldb.tirosh.ai/"
        viewModel.settings.remoteConsoleURL = "https://console.tirosh.ai/"
        viewModel.settings.changeAdminPassword = true
        viewModel.settings.adminPassword = "secret"
        viewModel.selectedBundleURL = URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")
        viewModel.selectedBundleSummary = "bundle summary"
        viewModel.selectedBundleVerification = "verification passed"
        viewModel.selectedBundleVerified = true
        viewModel.logText = "runtime log line\nwatchdog recovered"
        viewModel.releaseInfo = RuntimeReleaseInfo(
            helperVersion: "1.0",
            minimumUpdaterVersion: "1.0",
            vitalServerVersion: "2026.05.30",
            services: [
                RuntimeBundledServiceInfo(name: "vitalserver", image: "vitalserver:latest", version: "2026.05.30")
            ]
        )
    }

    private func runtimeServiceResource(service: String) -> RuntimeGuestServiceResource {
        RuntimeGuestServiceResource(
            service: service,
            spec: RuntimeGuestServiceSpec(
                state: "configured",
                desiredState: "running",
                updatedAt: "2026-07-11T00:00:00Z"
            ),
            status: RuntimeGuestServiceStatusRead(
                state: "loaded",
                observedState: "running",
                observedAt: "2026-07-11T00:00:00Z"
            ),
            conditions: []
        )
    }

    private func render<V: View>(
        _ view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1_100, height: 900)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0, file: file, line: line)
    }

    private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { subview in
            let current = (subview as? NSScrollView).map { [$0] } ?? []
            return current + descendantScrollViews(in: subview)
        }
    }
}

private extension RuntimeControlCapabilities {
    static var restricted: RuntimeControlCapabilities {
        RuntimeControlCapabilities(
            canInstallRuntime: false,
            canUninstallRuntime: false,
            canApplyBundle: false,
            canRollback: false,
            canEditRuntimeProviderResources: false,
            canEditNetworkExposure: false,
            canResetAdminPassword: false,
            canOpenLocalFiles: false,
            canStreamLogs: false,
            canControlRuntimeServices: false,
            canExportLogs: false,
            canViewReleaseMetadata: false
        )
    }
}

private struct NoopHealthNotifications: HealthNotifying {
    func configure() {}
    func notify(title: String, body: String) {}
}

@MainActor
private func loadedRedisRelaySettings(enabled: Bool) -> RuntimeRedisRelaySettingsRead {
    RuntimeRedisRelaySettingsRead(
        state: .loaded,
        settings: RuntimeRedisRelaySettingsReadDocument(
            enabled: enabled,
            target: RuntimeRedisRelayTargetRead(
                url: "redis://relay.example:6379/0",
                username: "relay-user",
                passwordConfigured: false,
                tls: false
            ),
            scope: .vitalReconstruction,
            includeRecorderNetworkContext: true,
            intervalSeconds: 1,
            scanCount: 1000
        ),
        readError: nil
    )
}

private final class FakeRuntimeClient: RuntimeControlClient, RuntimeHostClient {
    let capabilities: RuntimeControlCapabilities
    var loadStatusCount = 0
    var loadHealthStatusCount = 0
    var loadRuntimeEventsCount = 0
    var lastRuntimeEventQuery: RuntimeEventQuery?
    var runtimeEventQueries: [RuntimeEventQuery] = []
    var loadVitalDBRecordersCount = 0
    var loadVitalDBBedsCount = 0
    var loadVitalDBRecorderActivityWindowCount = 0
    var vitalDBRecorderActivityQueries: [RuntimeVitalRecorderActivityWindowQuery] = []
    var loadVitalDBRecorderVitalFilesCount = 0
    var vitalDBRecorderVitalFileVrcodes: [String] = []
    var loadRecorderObservabilityDetailCount = 0
    var recorderObservabilityDetailVrcodes: [String] = []
    var loadRedisRelayStatusCount = 0
    var runtimeStackStatusCount = 0
    var serviceResourceRequests: [String] = []
    var loadBackupsCount = 0
    var loadSettingsCount = 0
    var verifyUpdateBundleCount = 0
    var applySettingsCount = 0
    var restartVMRuntimeCount = 0
    var applyUpdateBundleCount = 0
    var rollbackRuntimeCount = 0
    var restoreRedisBackupCount = 0
    var restoreRuntimeDataBackupCount = 0
    var deleteBackupCount = 0
    var repairProxyCount = 0
    var repairDatastoreCount = 0
    var repairVMDiskCount = 0
    var repairRuntimeServicesCount = 0
    var createRedisBackupCount = 0
    var createRuntimeDataBackupCount = 0
    var startGuestServiceRequests: [RuntimeGuestServiceControlRequest] = []
    var stopGuestServiceRequests: [RuntimeGuestServiceControlRequest] = []
    var restartGuestServiceRequests: [RuntimeGuestServiceRestartRequest] = []
    var exportLogsCount = 0
    var loadReleaseInfoCount = 0
    var preferredLogsPathCount = 0
    var verifiedBundleURLs: [URL] = []
    var restoredRedisBackupURLs: [URL] = []
    var restoredRuntimeDataBackupURLs: [URL] = []
    var exportLogDestinationURLs: [URL] = []
    var deletedBackupURLs: [URL] = []
    var exportLogsResult: RuntimeLogExportResult?
    var releaseInfoLoadError: Error?
    var backupLoadError: Error?
    var redisRelayStatusError: Error?
    var runtimeStackError: Error?
    var vitalDBVisibilityError: Error?
    var serviceResourceErrorsByService: [String: Error] = [:]
    var serviceResourcesByService: [String: RuntimeGuestServiceResource] = [:]
    var labScenariosToLoad = RuntimeLabScenarioList(state: .loaded, scenarios: [])
    var labVitalFilesToLoad = RuntimeLabVitalFileList(state: .loaded, vitalFiles: [])
    var labBedsToLoad = RuntimeLabBedList(state: .loaded, beds: [])
    var labRecordersToLoad = RuntimeLabRecorderList(state: .loaded, recorders: [])
    var labSessionsToLoad = RuntimeLabSessionList.unavailable(
        readError: "Product Lab sessions are not configured in this test."
    )
    var labCreateRequests: [RuntimeLabSessionCreateRequest] = []
    var labReplayRequests: [RuntimeLabVitalFileReplayRequest] = []
    var labUploadRequests: [[RuntimeLabVitalFileUploadSource]] = []
    var labUploadResponse: RuntimeLabVitalFileLibraryUploadResponse?
    var labCreateBedRequests: [RuntimeLabBedCreateRequest] = []
    var labDeleteBedRequests: [RuntimeLabBedDeleteRequest] = []
    var labResetBedsCount = 0
    var labCreateRecorderRequests: [RuntimeLabRecorderCreateRequest] = []
    var labDeleteRecorderRequests: [RuntimeLabRecorderDeleteRequest] = []
    var labResetRecordersCount = 0
    var labStartedSessionIDs: [String] = []
    var labStoppedSessionIDs: [String] = []
    var labFinishedSessionIDs: [String] = []
    var labStartedRecorderRequests: [String] = []
    var labStoppedRecorderRequests: [String] = []
    var hiddenRecorderRequests: [RuntimeVitalDBRecorderVisibilityRequest] = []
    var unhiddenRecorderRequests: [RuntimeVitalDBRecorderVisibilityRequest] = []
    var deletedRecorderRequests: [RuntimeVitalDBRecorderVisibilityRequest] = []
    var hiddenBedRequests: [RuntimeVitalDBBedVisibilityRequest] = []
    var unhiddenBedRequests: [RuntimeVitalDBBedVisibilityRequest] = []
    var deletedBedRequests: [RuntimeVitalDBBedVisibilityRequest] = []
    var backupsToLoad: [RuntimeBackup] = []
    var redisBackupsToLoad: [RuntimeBackup] = []
    var runtimeDataBackupsToLoad: [RuntimeBackup] = []
    var lastLoadStatusSettings: RuntimeSettings?
    var lastLoadHealthStatusSettings: RuntimeSettings?
    var lastAppliedSettings: RuntimeSettings?
    var settings = RuntimeSettings()
    var status = platformState()
    var operationState = PlatformOperationState(activeOperation: nil, install: .unavailable())
    var healthStatus = platformState()
    var vitalDBObservation: VitalDBObservationDocument?
    var vitalDBVisibilityHistory = RuntimeVitalRecorderHistory(updatedAt: "2026-07-01T00:00:00+00:00")
    var vitalDBBedHistory = RuntimeVitalBedHistory()
    var vitalDBBedVisibilityHistory = RuntimeVitalBedHistory(updatedAt: "2026-07-01T00:00:00+00:00")
    var redisRelayStatusRead = RuntimeRedisRelayStatusReadResult(
        readState: .notRead,
        document: nil,
        readError: nil
    )
    var runtimeRedisRelaySettingsRead = loadedRedisRelaySettings(enabled: false)
    var appliedRuntimeRedisRelaySettings: [RuntimeRedisRelaySettingsApplyRequest] = []
    var runtimeStackStatus = RuntimeGuestControlStackStatus(
        state: "loaded",
        observedAt: "2026-07-11T00:00:00Z",
        services: []
    )

    init(capabilities: RuntimeControlCapabilities) {
        self.capabilities = capabilities
    }

    func loadSettings() -> RuntimeSettings {
        loadSettingsCount += 1
        return settings
    }

    func loadPlatformState(settings: RuntimeSettings) -> PlatformState {
        loadStatusCount += 1
        lastLoadStatusSettings = settings
        return status
    }

    func loadOperationState() -> PlatformOperationState {
        operationState
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
        loadHealthStatusCount += 1
        lastLoadHealthStatusSettings = settings
        return healthStatus
    }

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        loadRuntimeEventsCount += 1
        return RuntimeEventHistory(events: [])
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        loadRuntimeEventsCount += 1
        lastRuntimeEventQuery = query
        runtimeEventQueries.append(query)
        return RuntimeEventHistory(events: [])
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.fromOptional(vitalDBObservation)
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        loadVitalDBRecordersCount += 1
        return RuntimeVitalRecorderHistory()
    }

    func loadVitalDBBeds() -> RuntimeVitalBedHistory {
        loadVitalDBBedsCount += 1
        return vitalDBBedHistory
    }

    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) -> RuntimeVitalRecorderActivityWindow {
        loadVitalDBRecorderActivityWindowCount += 1
        vitalDBRecorderActivityQueries.append(query)
        return RuntimeVitalRecorderActivityWindowAssembler.makeWindow(
            query: query,
            bounds: nil,
            records: [],
            readError: nil
        )
    }

    func loadVitalDBRecorderVitalFiles(
        vrcode: String
    ) -> RuntimeVitalRecorderVitalFileHistory {
        loadVitalDBRecorderVitalFilesCount += 1
        vitalDBRecorderVitalFileVrcodes.append(vrcode)
        return RuntimeVitalRecorderVitalFileHistory(
            state: .loaded,
            vrcode: vrcode,
            sources: RuntimeVitalRecorderVitalFileSources(
                nativeUpload: RuntimeVitalRecorderVitalFileSourceRead(
                    state: .loaded,
                    readError: nil
                ),
                coldPathRecovery: RuntimeVitalRecorderVitalFileSourceRead(
                    state: .loaded,
                    readError: nil
                )
            ),
            readError: nil
        )
    }

    func loadRecorderObservabilityDetail(
        vrcode: String
    ) -> RuntimeRecorderObservabilityDetail {
        loadRecorderObservabilityDetailCount += 1
        recorderObservabilityDetailVrcodes.append(vrcode)
        return .unavailable(
            vrcode: vrcode,
            readError: "fixture observability detail is unavailable"
        )
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory()
    }

    func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult {
        loadRedisRelayStatusCount += 1
        if let redisRelayStatusError {
            throw redisRelayStatusError
        }
        return redisRelayStatusRead
    }

    func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead {
        runtimeRedisRelaySettingsRead
    }

    func applyRuntimeRedisRelaySettings(
        _ settings: RuntimeRedisRelaySettingsApplyRequest
    ) async throws -> RuntimeGuestControlServiceOperation {
        appliedRuntimeRedisRelaySettings.append(settings)
        return RuntimeGuestControlServiceOperation(
            operationId: "redis-relay-settings-1",
            service: "redis-relay",
            command: .applyRedisRelaySettings,
            state: .completed,
            createdAt: "2026-07-11T00:00:00Z",
            updatedAt: "2026-07-11T00:00:01Z"
        )
    }

    func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        runtimeStackStatusCount += 1
        if let runtimeStackError {
            throw runtimeStackError
        }
        return runtimeStackStatus
    }

    func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        serviceResourceRequests.append(service)
        if let error = serviceResourceErrorsByService[service] {
            throw error
        }
        guard let resource = serviceResourcesByService[service] else {
            throw RuntimeControlClientUnsupportedError.unavailable("service-resource-\(service)")
        }
        return resource
    }

    func hideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        hiddenRecorderRequests.append(request)
        if let vitalDBVisibilityError {
            throw vitalDBVisibilityError
        }
        return vitalDBVisibilityHistory
    }

    func unhideVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        unhiddenRecorderRequests.append(request)
        if let vitalDBVisibilityError {
            throw vitalDBVisibilityError
        }
        return vitalDBVisibilityHistory
    }

    func deleteVitalDBRecorders(
        _ request: RuntimeVitalDBRecorderVisibilityRequest
    ) async throws -> RuntimeVitalRecorderHistory {
        deletedRecorderRequests.append(request)
        if let vitalDBVisibilityError {
            throw vitalDBVisibilityError
        }
        return vitalDBVisibilityHistory
    }

    func hideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        hiddenBedRequests.append(request)
        return vitalDBBedVisibilityHistory
    }

    func unhideVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        unhiddenBedRequests.append(request)
        return vitalDBBedVisibilityHistory
    }

    func deleteVitalDBBeds(
        _ request: RuntimeVitalDBBedVisibilityRequest
    ) async throws -> RuntimeVitalBedHistory {
        deletedBedRequests.append(request)
        return vitalDBBedVisibilityHistory
    }

    func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup] {
        loadBackupsCount += 1
        if let backupLoadError {
            throw backupLoadError
        }
        return backupsToLoad
    }

    func loadRedisBackups() throws -> [RuntimeBackup] {
        redisBackupsToLoad
    }

    func loadRuntimeDataBackups() throws -> [RuntimeBackup] {
        runtimeDataBackupsToLoad
    }

    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult {
        .loaded("bundle: \(url.path)")
    }

    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult {
        .loaded("log:\(sourceID.rawValue):\(lineLimit)")
    }

    func loadLogTextResult(sourceID: RuntimeLogSource, lineLimit: Int) async -> RuntimeHostTextReadResult {
        logTextResult(sourceID: sourceID, lineLimit: lineLimit)
    }

    func preferredLogsPath() -> String {
        preferredLogsPathCount += 1
        return "/logs"
    }

    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] {
        []
    }

    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        verifyUpdateBundleCount += 1
        verifiedBundleURLs.append(url)
        return success()
    }

    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeCommandResult {
        success()
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        applySettingsCount += 1
        lastAppliedSettings = settings
        return success()
    }

    func restartVMRuntime(applying settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        restartVMRuntimeCount += 1
        lastAppliedSettings = settings
        return success()
    }

    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        applyUpdateBundleCount += 1
        return success()
    }

    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        rollbackRuntimeCount += 1
        return success()
    }

    func restoreRedisBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        restoreRedisBackupCount += 1
        restoredRedisBackupURLs.append(backupURL)
        return success()
    }

    func restoreRuntimeDataBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        restoreRuntimeDataBackupCount += 1
        restoredRuntimeDataBackupURLs.append(backupURL)
        return success()
    }

    func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        deleteBackupCount += 1
        deletedBackupURLs.append(url)
        return success()
    }

    func repairProxy() async throws -> RuntimeCommandResult {
        repairProxyCount += 1
        return success()
    }

    func repairDatastore() async throws -> RuntimeCommandResult {
        repairDatastoreCount += 1
        return success()
    }

    func repairVMDisk() async throws -> RuntimeCommandResult {
        repairVMDiskCount += 1
        return success()
    }

    func repairRuntimeServices() async throws -> RuntimeCommandResult {
        repairRuntimeServicesCount += 1
        return success()
    }

    func createRedisBackup() async throws -> RuntimeCommandResult {
        createRedisBackupCount += 1
        return success()
    }

    func createRuntimeDataBackup() async throws -> RuntimeCommandResult {
        createRuntimeDataBackupCount += 1
        return success()
    }

    func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        labScenariosToLoad
    }

    func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        labVitalFilesToLoad
    }

    func loadLabBeds() async throws -> RuntimeLabBedList {
        labBedsToLoad
    }

    func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        labRecordersToLoad
    }

    func loadLabSessions() async throws -> RuntimeLabSessionList {
        labSessionsToLoad
    }

    func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        labCreateBedRequests.append(request)
        labBedsToLoad = RuntimeLabBedList(
            state: .loaded,
            beds: [
                RuntimeLabBed(
                    bedId: "lab-session-1-bed-1",
                    sessionId: "lab-session-1",
                    name: request.prefix ?? "Lab bed",
                    state: .accepted
                ),
            ]
        )
        labRecordersToLoad = RuntimeLabRecorderList(
            state: .loaded,
            recorders: [
                RuntimeLabRecorder(
                    recorderId: "lab-session-1-recorder-1",
                    sessionId: "lab-session-1",
                    bedId: "lab-session-1-bed-1",
                    vrcode: "LAB-lab-session-1-1",
                    state: .accepted
                ),
            ]
        )
        return labBedsToLoad
    }

    func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        labDeleteBedRequests.append(request)
        labBedsToLoad = RuntimeLabBedList(state: .loaded, beds: [])
        labRecordersToLoad = RuntimeLabRecorderList(state: .loaded, recorders: [])
        return labBedsToLoad
    }

    func resetLabBeds() async throws -> RuntimeLabBedList {
        labResetBedsCount += 1
        labBedsToLoad = RuntimeLabBedList(state: .loaded, beds: [])
        labRecordersToLoad = RuntimeLabRecorderList(state: .loaded, recorders: [])
        return labBedsToLoad
    }

    func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        labCreateRecorderRequests.append(request)
        labRecordersToLoad = RuntimeLabRecorderList(
            state: .loaded,
            recorders: [
                RuntimeLabRecorder(
                    recorderId: "lab-session-1-recorder-1",
                    sessionId: "lab-session-1",
                    bedId: "lab-session-1-bed-1",
                    vrcode: "LAB-lab-session-1-1",
                    state: .accepted
                ),
            ]
        )
        return labRecordersToLoad
    }

    func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        labDeleteRecorderRequests.append(request)
        labRecordersToLoad = RuntimeLabRecorderList(state: .loaded, recorders: [])
        return labRecordersToLoad
    }

    func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        labResetRecordersCount += 1
        labRecordersToLoad = RuntimeLabRecorderList(state: .loaded, recorders: [])
        return labRecordersToLoad
    }

    func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        labCreateRequests.append(request)
        return RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: "lab-session-1",
                state: .accepted,
                scenarioId: request.scenarioId,
                name: request.name,
                recorderCount: request.recorderCount,
                targetURL: request.targetURL ?? "http://edge/"
            ),
            operationId: "operation-1"
        )
    }

    func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: sessionId,
                state: .running,
                scenarioId: "case-a",
                recorderCount: 1,
                targetURL: "http://edge/"
            )
        )
    }

    func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        labStartedSessionIDs.append(sessionId)
        return RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: sessionId,
                state: .running,
                scenarioId: "case-a",
                recorderCount: 1,
                targetURL: "http://edge/"
            ),
            operationId: "operation-start"
        )
    }

    func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        labStoppedSessionIDs.append(sessionId)
        return RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: sessionId,
                state: .stopped,
                scenarioId: "case-a",
                recorderCount: 1,
                targetURL: "http://edge/"
            ),
            operationId: "operation-stop"
        )
    }

    func finishLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        labFinishedSessionIDs.append(sessionId)
        return RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: sessionId,
                state: .finished,
                scenarioId: "case-a",
                recorderCount: 1,
                targetURL: "http://edge/"
            ),
            operationId: "operation-finish"
        )
    }

    func startLabRecorder(
        sessionId: String,
        recorderId: String
    ) async throws -> RuntimeLabRecorderResponse {
        labStartedRecorderRequests.append("\(sessionId)/\(recorderId)")
        return labRecorderCommandResponse(
            sessionId: sessionId,
            recorderId: recorderId,
            state: .running
        )
    }

    func stopLabRecorder(
        sessionId: String,
        recorderId: String
    ) async throws -> RuntimeLabRecorderResponse {
        labStoppedRecorderRequests.append("\(sessionId)/\(recorderId)")
        return labRecorderCommandResponse(
            sessionId: sessionId,
            recorderId: recorderId,
            state: .stopped
        )
    }

    private func labRecorderCommandResponse(
        sessionId: String,
        recorderId: String,
        state: RuntimeLabSessionState
    ) -> RuntimeLabRecorderResponse {
        guard let recorder = labRecordersToLoad.recorders.first(where: {
            $0.sessionId == sessionId && $0.recorderId == recorderId
        }) else {
            return .unavailable(readError: "recorder is not owned by session")
        }
        let updated = RuntimeLabRecorder(
            recorderId: recorder.recorderId,
            sessionId: recorder.sessionId,
            bedId: recorder.bedId,
            vrcode: recorder.vrcode,
            state: state,
            messagesSent: recorder.messagesSent,
            lastSendState: recorder.lastSendState,
            lastSendAt: recorder.lastSendAt,
            lastSendError: recorder.lastSendError
        )
        labRecordersToLoad = RuntimeLabRecorderList(
            state: .loaded,
            recorders: labRecordersToLoad.recorders.map {
                $0.recorderId == recorderId ? updated : $0
            }
        )
        return RuntimeLabRecorderResponse(
            state: .loaded,
            recorder: updated,
            operationId: "operation-recorder"
        )
    }

    func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        labReplayRequests.append(request)
        return RuntimeLabSessionResponse(
            state: .loaded,
            session: RuntimeLabSession(
                sessionId: "lab-replay-1",
                state: .accepted,
                scenarioId: "vital-file",
                name: request.sessionName,
                recorderCount: 1,
                targetURL: request.targetURL ?? "http://edge/"
            ),
            operationId: "operation-replay"
        )
    }

    func uploadLabVitalFiles(
        _ sources: [RuntimeLabVitalFileUploadSource]
    ) async throws -> RuntimeLabVitalFileLibraryUploadResponse {
        labUploadRequests.append(sources)
        if let labUploadResponse {
            return labUploadResponse
        }
        return RuntimeLabVitalFileLibraryUploadResponse(files: sources.map {
            RuntimeLabVitalFileLibraryUploadItem(
                fileName: $0.fileName,
                relativePath: $0.fileName,
                sizeBytes: Int($0.sizeBytes)
            )
        })
    }

    func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        startGuestServiceRequests.append(request)
        return guestServiceOperation(service: request.service, command: .start)
    }

    func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        stopGuestServiceRequests.append(request)
        return guestServiceOperation(service: request.service, command: .stop)
    }

    func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        restartGuestServiceRequests.append(request)
        return guestServiceOperation(service: request.service, command: .restart)
    }

    private func guestServiceOperation(
        service: String,
        command: RuntimeGuestControlServiceCommand
    ) -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "\(command.rawValue)-\(service)",
            service: service,
            command: command,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00"
        )
    }

    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        exportLogsCount += 1
        exportLogDestinationURLs.append(destination)
        return exportLogsResult ?? RuntimeLogExportResult(destination: destination)
    }

    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        loadReleaseInfoCount += 1
        if let releaseInfoLoadError {
            throw releaseInfoLoadError
        }
        return RuntimeReleaseInfo(
            helperVersion: "test",
            minimumUpdaterVersion: "test",
            vitalServerVersion: "test",
            services: []
        )
    }

    func loadInstallInfo() -> RuntimeInstallInfo {
        RuntimeInstallInfo(
            runtimeHomePath: "/runtime",
            backupsPath: "/backups",
            redisBackupsPath: "/platform/backups/runtime-data/redis",
            runtimeDataBackupsPath: "/platform/backups/runtime-data/vitalserver-helper"
        )
    }

    private func success() -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

@MainActor
private final class FakeRuntimeNativeShell: RuntimeNativeShell {
    var directoryURL: URL?
    var updateBundleURL: URL?
    var redisBackupArchiveURL: URL?
    var vitalFileURLs: [URL] = []
    var vitalFileUploadSources: [RuntimeLabVitalFileUploadSource] = []
    var readVitalFileSources: [[URL]] = []
    var logExportDestinationURL: URL?
    var logExportDestinationValidationMessages: [String: String] = [:]
    var chooseDirectoryPrompts: [String] = []
    var chooseUpdateBundlePrompts: [String] = []
    var chooseRedisBackupArchivePrompts: [String] = []
    var chooseVitalFilesPrompts: [String] = []
    var chooseVitalFilesDirectoryURLs: [URL?] = []
    var chooseLogExportDestinationPrompts: [String] = []
    var openedFileURLs: [URL] = []
    var openedWebURLs: [URL] = []
    var existingDirectories: Set<String>?
    var pathStates: [String: RuntimePathState] = [:]
    var confirmCreateDirectoryResponses: [Bool] = []
    var confirmCreateDirectoryPaths: [String] = []
    var createdDirectoryURLs: [URL] = []
    var copiedDirectories: [(source: URL, destination: URL)] = []
    var copiedFiles: [(source: URL, destination: URL)] = []
    var copyFileError: Error?
    var copyDirectoryError: Error?
    var relaunchHelperCount = 0
    var terminateCount = 0

    var chooseDirectoryCount: Int {
        chooseDirectoryPrompts.count
    }

    var chooseUpdateBundleCount: Int {
        chooseUpdateBundlePrompts.count
    }

    var chooseRedisBackupArchiveCount: Int {
        chooseRedisBackupArchivePrompts.count
    }

    var chooseVitalFilesCount: Int {
        chooseVitalFilesPrompts.count
    }

    var chooseLogExportDestinationCount: Int {
        chooseLogExportDestinationPrompts.count
    }

    func chooseDirectory(prompt: String) -> URL? {
        chooseDirectoryPrompts.append(prompt)
        return directoryURL
    }

    func chooseUpdateBundle(prompt: String) -> URL? {
        chooseUpdateBundlePrompts.append(prompt)
        return updateBundleURL
    }

    func chooseRedisBackupArchive(prompt: String) -> URL? {
        chooseRedisBackupArchivePrompts.append(prompt)
        return redisBackupArchiveURL
    }

    func chooseVitalFiles(prompt: String, directoryURL: URL?) -> [URL] {
        chooseVitalFilesPrompts.append(prompt)
        chooseVitalFilesDirectoryURLs.append(directoryURL)
        return vitalFileURLs
    }

    func readVitalFileUploadSources(
        _ sources: [URL]
    ) throws -> [RuntimeLabVitalFileUploadSource] {
        readVitalFileSources.append(sources)
        return vitalFileUploadSources
    }

    func chooseLogExportDestination(defaultName: String, prompt: String) -> URL? {
        chooseLogExportDestinationPrompts.append(prompt)
        return logExportDestinationURL
    }

    func logExportDestinationValidationMessage(for url: URL) -> String? {
        logExportDestinationValidationMessages[url.path]
    }

    func pathState(_ url: URL) -> RuntimePathState {
        if let pathState = pathStates[url.path] {
            return pathState
        }
        guard let existingDirectories else {
            return .directory
        }
        return existingDirectories.contains(url.path) ? .directory : .missing
    }

    func confirmCreateDirectory(path: String) -> Bool {
        confirmCreateDirectoryPaths.append(path)
        return confirmCreateDirectoryResponses.isEmpty ? false : confirmCreateDirectoryResponses.removeFirst()
    }

    func createDirectory(_ url: URL) throws {
        createdDirectoryURLs.append(url)
        existingDirectories?.insert(url.path)
        pathStates[url.path] = .directory
    }

    func copyFile(_ source: URL, to destination: URL) throws {
        if let copyFileError {
            throw copyFileError
        }
        copiedFiles.append((source: source, destination: destination))
        pathStates[destination.path] = .file
    }

    func copyDirectory(_ source: URL, to destination: URL) throws {
        if let copyDirectoryError {
            throw copyDirectoryError
        }
        copiedDirectories.append((source: source, destination: destination))
        pathStates[destination.path] = .directory
    }

    func openFileURL(_ url: URL) {
        openedFileURLs.append(url)
    }

    func openWebURL(_ url: URL) {
        openedWebURLs.append(url)
    }

    func relaunchHelper() {
        relaunchHelperCount += 1
    }

    func terminate() {
        terminateCount += 1
    }
}

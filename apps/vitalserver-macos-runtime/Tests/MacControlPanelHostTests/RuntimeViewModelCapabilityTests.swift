import Foundation
import Contracts
import Application
import Domain
import RuntimeControl
@testable import MacControlPanelHost
import SwiftUI
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeViewModelCapabilityTests: XCTestCase {
    func testViewModelInitializesStatusFromExplicitControlClientRead() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.status = RuntimeStatus(runtimeInstalled: true, statusMessage: "initial status")

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadStatusCount, 1)
        XCTAssertEqual(viewModel.status.statusMessage, "initial status")
        XCTAssertTrue(viewModel.status.runtimeInstalled)
    }

    func testViewModelInitialSettingsResolutionReadsControlSettingsOnceBeforeLocalPortOverride() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.settings.runtimeControlPort = 44080
        let localAPISettings = FakeLocalAPISettings(runtimeControlPort: 55080)

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            localAPISettings: localAPISettings,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadSettingsCount, 1)
        XCTAssertEqual(viewModel.settings.runtimeControlPort, 55080)
        XCTAssertEqual(localAPISettings.settingsWithLocalAPIPortCount, 1)
    }

    func testViewModelInitialSettingsUsesExplicitInputWithoutControlSettingsRead() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        var initialSettings = RuntimeSettings()
        initialSettings.runtimeControlPort = 44080
        let localAPISettings = FakeLocalAPISettings(runtimeControlPort: 55080)

        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            initialSettings: initialSettings,
            localAPISettings: localAPISettings,
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadSettingsCount, 0)
        XCTAssertEqual(viewModel.settings.runtimeControlPort, 55080)
        XCTAssertEqual(localAPISettings.settingsWithLocalAPIPortCount, 1)
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
            initialStatus: RuntimeStatus(runtimeInstalled: true, statusMessage: "provided"),
            healthNotifications: NoopHealthNotifications()
        )

        XCTAssertEqual(client.loadStatusCount, 0)
        XCTAssertEqual(viewModel.status.statusMessage, "provided")
        XCTAssertTrue(viewModel.status.runtimeInstalled)
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
        await viewModel.startRuntimeServices()
        await viewModel.stopRuntimeServices()
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
        XCTAssertEqual(client.startRuntimeServicesCount, 0)
        XCTAssertEqual(client.stopRuntimeServicesCount, 0)
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
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.status = RuntimeStatus(proxyPort: nil)
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: FakeRuntimeNativeShell()
        )

        await viewModel.repairProxyPort()

        XCTAssertEqual(client.repairProxyCount, 1)
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
            RuntimeBackup(path: "/runtime/data/backups/vitalserver-helper/selected", sizeBytes: nil)
        ]
        let viewModel = RuntimeViewModel(controlClient: client, hostClient: client, healthNotifications: NoopHealthNotifications())
        viewModel.runtimeDataBackups = [
            RuntimeBackup(path: "/runtime/data/backups/vitalserver-helper/selected", sizeBytes: nil)
        ]
        viewModel.selectedRuntimeDataBackupPath = "/runtime/data/backups/vitalserver-helper/selected"

        await viewModel.createRuntimeDataBackup()
        await viewModel.restoreRuntimeDataBackup()
        await viewModel.deleteSelectedRuntimeDataBackup()

        XCTAssertEqual(client.createRuntimeDataBackupCount, 1)
        XCTAssertEqual(client.restoreRuntimeDataBackupCount, 1)
        XCTAssertEqual(client.deleteBackupCount, 1)
        XCTAssertEqual(client.restoredRuntimeDataBackupURLs, [
            URL(fileURLWithPath: "/runtime/data/backups/vitalserver-helper/selected")
        ])
        XCTAssertEqual(client.deletedBackupURLs, [
            URL(fileURLWithPath: "/runtime/data/backups/vitalserver-helper/selected")
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

    func testRestartVMRuntimeFromSettingsUsesRuntimeServiceRestartPort() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.restartVMRuntimeFromSettings()

        XCTAssertEqual(client.repairRuntimeServicesCount, 1)
        XCTAssertEqual(client.loadHealthStatusCount, 0)
        XCTAssertGreaterThanOrEqual(client.loadStatusCount, 2)
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
            URL(fileURLWithPath: "/runtime/data/backups/redis"),
            URL(fileURLWithPath: "/runtime/data/backups/vitalserver-helper"),
        ])
        XCTAssertEqual(nativeShell.openedWebURLs, [
            URL(string: RuntimeControlLocalAPIConstants.pwaURL),
            URL(string: AppConstants.Product.vitalDBURL),
        ])
        XCTAssertEqual(nativeShell.chooseLogExportDestinationPrompts, [AppConstants.Actions.exportLogs])
        XCTAssertEqual(client.exportLogDestinationURLs, [exportURL])
    }

    func testImportRuntimeDataBackupCopiesSelectedFolderIntoManagedRuntimeDataBackupRoot() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let sourceURL = URL(fileURLWithPath: "/external/20260614T043455Z-manual", isDirectory: true)
        let destinationURL = URL(fileURLWithPath: "/runtime/data/backups/vitalserver-helper/20260614T043455Z-manual", isDirectory: true)
        nativeShell.directoryURL = sourceURL
        nativeShell.pathStates = [
            sourceURL.path: .directory,
            "/runtime/data/backups/vitalserver-helper": .directory,
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
        let destinationURL = URL(fileURLWithPath: "/runtime/data/backups/redis/redis-20260614T043455Z.tar.gz")
        nativeShell.redisBackupArchiveURL = sourceURL
        nativeShell.pathStates = [
            sourceURL.path: .file,
            "/runtime/data/backups/redis": .directory,
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
            "/runtime/data/backups/redis": .directory,
            "/runtime/data/backups/redis/redis-20260614T043455Z.tar.gz": .file,
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
        let selectedURL = URL(fileURLWithPath: "/runtime/data/backups/redis/redis-20260614T043455Z.tar.gz")
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
            "/runtime/data/backups/vitalserver-helper": .directory,
            "/runtime/data/backups/vitalserver-helper/20260614T043455Z-manual": .directory,
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

    func testHealthRefreshUpdatesContainerObservationForServiceHealth() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let observation = RuntimeContainerObservation(
            recorderIngressHTTP: "200",
            recorderIngressStatus: nil,
            runtimeStateUpdatedAt: "2026-06-05T00:00:00Z",
            runtimeStateFileUpdatedAt: "2026-06-05T00:00:00Z",
            containerLogsPresent: true,
            containerLogsBytes: 1,
            composeServices: [
                RuntimeContainerServiceObservation(
                    service: "vitaldb-observer",
                    state: "running",
                    health: "healthy",
                    exitCode: 0,
                    uptimeSeconds: 42
                ),
            ]
        )
        client.healthStatus = RuntimeStatus(containerObservation: observation)
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshHealthStatus()

        XCTAssertEqual(viewModel.containerObservation, observation)
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
        XCTAssertNil(viewModel.status.vitalDBObservation)
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

    func testTestKitStartRequiresAvailableBeds() {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.testKitStatus = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            sessions: [
                testKitSession(
                    id: "session-a",
                    state: "running",
                    bedRoomNames: ["OR-A"]
                )
            ],
            beds: [RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a")]
        )

        XCTAssertFalse(viewModel.testKitCanStart)
        XCTAssertFalse(viewModel.testKitCanResetBeds)
    }

    func testTestKitContainerControlsAreIndependentOfContainerState() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities(
            canControlRuntimeServices: true
        ))
        let testKit = FakeTestKitController()
        testKit.status = RuntimeTestKitStatus(enabled: true, state: .stopped)
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.testKitStatus = testKit.status

        XCTAssertTrue(viewModel.testKitCanControlContainer)

        await viewModel.startTestKitContainer()
        await viewModel.stopTestKitContainer()
        await viewModel.restartTestKitContainer()

        XCTAssertEqual(client.startTestKitServiceCount, 1)
        XCTAssertEqual(client.stopTestKitServiceCount, 1)
        XCTAssertEqual(client.restartTestKitServiceCount, 1)
    }

    func testTestKitStartUsesSelectedBedRoomNames() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            sessions: [
                testKitSession(
                    id: "session-a",
                    state: "running",
                    bedRoomNames: ["OR-A"]
                )
            ],
            beds: [
                RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"),
                RuntimeTestKitBed(roomName: "OR-B", bedID: "bed-b"),
            ]
        )
        testKit.status = status
        viewModel.testKitStatus = status
        viewModel.setTestKitBedSelection("OR-B", selected: true)

        await viewModel.startVirtualRecorderSession()

        XCTAssertEqual(testKit.startedRequests.count, 1)
        XCTAssertEqual(testKit.startedRequests[0].bedroomName, "OR-B")
    }

    func testTestKitResetBedsRequiresNoActiveSessions() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.testKitStatus = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            sessions: [
                testKitSession(
                    id: "session-a",
                    state: "running",
                    bedRoomNames: ["OR-A"]
                )
            ],
            beds: [RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a")]
        )

        await viewModel.resetTestKitBeds()

        XCTAssertEqual(testKit.resetBedsCount, 0)
        XCTAssertEqual(
            viewModel.testKitActionMessage,
            RuntimeTestPanelText.stopSessionsBeforeResettingBeds
        )
        XCTAssertEqual(viewModel.testKitActionMessageTone, .failure)
    }

    func testTestKitDeletesSelectedInactiveBed() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            beds: [
                RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"),
                RuntimeTestKitBed(roomName: "OR-B", bedID: "bed-b"),
            ]
        )
        testKit.status = status
        viewModel.testKitStatus = status
        viewModel.setTestKitBedSelection("OR-A", selected: true)

        await viewModel.deleteTestKitBed(RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"))

        XCTAssertEqual(testKit.deletedBedRequests.map(\.roomNames), [["OR-A"]])
        XCTAssertEqual(viewModel.testKitStatus.beds.map(\.roomName), ["OR-B"])
        XCTAssertFalse(viewModel.testKitBedIsSelected("OR-A"))
    }

    func testTestKitActionsUpdateStatusAndMessages() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        testKit.status = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            beds: [
                RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a"),
                RuntimeTestKitBed(roomName: "OR-B", bedID: "bed-b"),
            ]
        )
        await viewModel.refreshTestKitStatus()

        viewModel.setTestKitBedSelection("OR-A", selected: true)
        await viewModel.startVirtualRecorderSession()
        let sessionID = viewModel.selectedTestKitSessionID

        await viewModel.pauseVirtualRecorderSession(sessionID: sessionID)
        await viewModel.resumeVirtualRecorderSession(sessionID: sessionID)
        await viewModel.stopVirtualRecorderSession(sessionID: sessionID)
        await viewModel.restartVirtualRecorderSession(session: testKitSession(
            id: sessionID,
            state: "stopped",
            bedRoomNames: ["OR-A"]
        ))
        await viewModel.deleteVirtualRecorderSession(sessionID: viewModel.selectedTestKitSessionID)

        viewModel.testKitOrphanVrcode = " VR_ORPHAN "
        await viewModel.deleteOrphanVirtualRecorder()
        await viewModel.resetVirtualRecorderSessions()
        await viewModel.resetTestKitBeds()
        viewModel.testKitBedCount = 2
        viewModel.testKitBedPrefix = "ICU"
        await viewModel.createTestKitBeds()

        XCTAssertEqual(testKit.startedRequests.count, 1)
        XCTAssertEqual(testKit.pausedSessionIDs, [sessionID])
        XCTAssertEqual(testKit.resumedSessionIDs, [sessionID])
        XCTAssertEqual(testKit.stoppedSessionIDs, [sessionID])
        XCTAssertEqual(testKit.deletedRecorderVRCodes, ["VR_ORPHAN"])
        XCTAssertEqual(testKit.resetSessionsCount, 1)
        XCTAssertEqual(testKit.resetBedsCount, 1)
        XCTAssertEqual(viewModel.testKitStatus.beds.map(\.roomName), ["ICU-1", "ICU-2"])
        XCTAssertEqual(viewModel.selectedTestKitBedCount, 2)
        XCTAssertEqual(viewModel.testKitActionMessageTone, .neutral)
    }

    func testCreateTestKitBedsCanUseExactBedNameWithoutRandomSuffix() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )

        viewModel.testKitBedPrefix = "MORC03"
        viewModel.testKitBedCount = 4
        viewModel.testKitAppendRandomBedSuffix = false

        await viewModel.createTestKitBeds()

        XCTAssertEqual(viewModel.testKitStatus.beds.map(\.roomName), ["MORC03"])
        XCTAssertEqual(testKit.createdRequests.last?.count, 1)
        XCTAssertEqual(testKit.createdRequests.last?.prefix, "MORC03")
        XCTAssertEqual(testKit.createdRequests.last?.appendRandomSuffix, false)
    }

    func testManualVitalUploadSelectsFilesAndUsesHostProxyUploadURL() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        client.status = RuntimeStatus(proxyPort: 18080)
        let testKit = FakeTestKitController()
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.vitalFileURLs = [
            URL(fileURLWithPath: "/data/MORC03_260617_120000.vital"),
            URL(fileURLWithPath: "/data/MORC04_260617_120100.vital"),
        ]
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            initialStatus: client.status,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await viewModel.uploadVitalFilesFromTestTab()

        XCTAssertEqual(nativeShell.chooseVitalFilesPrompts, [RuntimeTestPanelText.choosingVitalFiles])
        XCTAssertEqual(testKit.vitalUploadRequests.count, 1)
        XCTAssertEqual(testKit.vitalUploadRequests[0].filePaths, [
            "/data/MORC03_260617_120000.vital",
            "/data/MORC04_260617_120100.vital",
        ])
        XCTAssertEqual(testKit.vitalUploadRequests[0].vitalServerBaseURL, "http://127.0.0.1:18080/")
        XCTAssertEqual(testKit.vitalUploadRequests[0].endpoint, "/upload")
        XCTAssertEqual(viewModel.testKitActionMessage, "Uploaded 2/2 .vital files · beds 2 · failed 0")
        XCTAssertEqual(viewModel.testKitActionMessageTone, .neutral)
    }

    func testTestKitActionsReportUnavailableOrInvalidInputs() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.refreshTestKitStatus()
        await viewModel.createTestKitBeds()
        await viewModel.resetTestKitBeds()
        await viewModel.startVirtualRecorderSession()
        await viewModel.stopVirtualRecorderSession()
        await viewModel.deleteVirtualRecorderSession(sessionID: nil)
        await viewModel.resetVirtualRecorderSessions()
        await viewModel.deleteOrphanVirtualRecorder()

        XCTAssertEqual(viewModel.testKitStatus.state, .disabled)
        XCTAssertEqual(viewModel.testKitActionMessage, RuntimeTestPanelText.testKitUnavailable)
        XCTAssertEqual(viewModel.testKitActionMessageTone, .failure)

        let testKit = FakeTestKitController()
        let controlled = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        await controlled.deleteOrphanVirtualRecorder()

        XCTAssertEqual(controlled.testKitActionMessage, RuntimeTestPanelText.missingVrcode)
        XCTAssertEqual(controlled.testKitActionMessageTone, .failure)
    }

    func testTestKitSessionActionsRequirePresentationSelectedSession() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )

        await viewModel.pauseVirtualRecorderSession(sessionID: nil)
        await viewModel.deleteVirtualRecorderSession(sessionID: "   ")

        XCTAssertEqual(viewModel.testKitActionMessage, RuntimeTestPanelText.noActiveSession)
        XCTAssertEqual(viewModel.testKitActionMessageTone, .failure)
        XCTAssertTrue(testKit.pausedSessionIDs.isEmpty)
        XCTAssertTrue(testKit.deletedSessionIDs.isEmpty)
    }

    func testTestKitActionFailurePreservesExplicitControllerStatus() async {
        let client = FakeRuntimeClient(capabilities: RuntimeControlCapabilities())
        let testKit = FakeTestKitController()
        testKit.startError = NSError(
            domain: "RuntimeViewModelCapabilityTests",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "start denied"]
        )
        testKit.status = RuntimeTestKitStatus(
            enabled: true,
            state: .failed,
            beds: [RuntimeTestKitBed(roomName: "OR-A", bedID: "bed-a")],
            lastError: "controller reports failed state",
            readIssues: [
                RuntimeTestKitReadIssue(source: "testkitAPI", message: "status read degraded"),
            ]
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            testKitController: testKit,
            healthNotifications: NoopHealthNotifications()
        )
        viewModel.testKitStatus = testKit.status
        viewModel.setTestKitBedSelection("OR-A", selected: true)

        await viewModel.startVirtualRecorderSession()

        XCTAssertEqual(viewModel.message, "start denied")
        XCTAssertEqual(viewModel.testKitActionMessage, "start denied")
        XCTAssertEqual(viewModel.testKitActionMessageTone, .failure)
        XCTAssertEqual(viewModel.testKitStatus.state, .failed)
        XCTAssertEqual(viewModel.testKitStatus.lastError, "controller reports failed state")
        XCTAssertEqual(viewModel.testKitStatus.readIssues, [
            RuntimeTestKitReadIssue(source: "testkitAPI", message: "status read degraded"),
        ])
        XCTAssertFalse(viewModel.isRunningTestKitAction)
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
            showingStartServicesConfirmation: .constant(false),
            showingStopServicesConfirmation: .constant(false),
            hoveredServiceLink: Binding<String?>(get: { nil }, set: { _ in }),
            showingRecoveryOperations: true,
            showingAdvancedRepairTools: true,
            showingNetworkOverrides: true,
            showingAdminOperations: true
        ))
        render(RuntimeTestPanel(viewModel: viewModel))
        render(ContentView().environmentObject(viewModel))
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
        viewModel.status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            guestLogSyncServiceLoaded: true,
            sleepPreventionServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            operation: .none,
            statusMessage: "healthy",
            updatedAt: observedAt,
            startedAt: observedAt,
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
            cpuUsagePercent: 12.5,
            memory: ResourceUsage(usedBytes: 512 * 1024 * 1024, totalBytes: 2 * 1024 * 1024 * 1024),
            systemDisk: ResourceUsage(usedBytes: 10 * 1024 * 1024, totalBytes: 100 * 1024 * 1024),
            dataStorage: ResourceUsage(usedBytes: 20 * 1024 * 1024, totalBytes: 200 * 1024 * 1024),
            proxyPort: 8080,
            vitalDBObservation: observation
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
        viewModel.testKitStatus = RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            serviceName: "testkit",
            apiBaseURL: "http://127.0.0.1:18081",
            recorderTargetURL: "http://127.0.0.1",
            sessions: [testKitSession(id: "session-001", state: "running", bedRoomNames: ["OR-1"])],
            beds: [RuntimeTestKitBed(roomName: "OR-1", bedID: "bed-001")]
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
}

private extension RuntimeControlCapabilities {
    static var restricted: RuntimeControlCapabilities {
        RuntimeControlCapabilities(
            canInstallRuntime: false,
            canUninstallRuntime: false,
            canApplyBundle: false,
            canRollback: false,
            canEditVMResources: false,
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

private func testKitSession(
    id: String,
    state: String,
    bedRoomNames: [String]
) -> RuntimeTestKitSession {
    RuntimeTestKitSession(
        id: id,
        state: state,
        targetURL: "http://example.test",
        recordersRequested: bedRoomNames.count,
        bedsRequested: bedRoomNames.count,
        bedroomName: bedRoomNames.first ?? "TestBedroom",
        bedRoomNames: bedRoomNames,
        vrcode: nil,
        version: "testkit",
        intervalSeconds: 1,
        durationSeconds: nil,
        maxMessages: nil,
        shiftTime: true,
        generateFrames: true,
        scenario: "normal_monitoring",
        createdAt: nil,
        startedAt: nil,
        stoppedAt: nil,
        messagesSent: 0,
        bytesSent: 0,
        lastError: nil,
        recorders: []
    )
}

private struct NoopHealthNotifications: HealthNotifying {
    func configure() {}
    func notify(title: String, body: String) {}
}

@MainActor
private final class FakeTestKitController: RuntimeTestKitControlling, RuntimeTestKitVitalFileUploading {
    var status = RuntimeTestKitStatus(enabled: true, state: .running)
    var startedRequests: [RuntimeTestKitVirtualRecorderStartRequest] = []
    var resetBedsCount = 0
    var resetSessionsCount = 0
    var deletedBedRequests: [RuntimeTestKitDeleteBedsRequest] = []
    var startError: Error?
    var stoppedSessionIDs: [String?] = []
    var pausedSessionIDs: [String?] = []
    var resumedSessionIDs: [String?] = []
    var restartedSessionIDs: [String?] = []
    var deletedSessionIDs: [String?] = []
    var deletedRecorderVRCodes: [String] = []
    var createdRequests: [RuntimeTestKitCreateBedsRequest] = []
    var vitalUploadRequests: [RuntimeTestKitVitalFileUploadRequest] = []

    func loadTestKitStatus() async -> RuntimeTestKitStatus {
        status
    }

    func createTestKitBeds(_ request: RuntimeTestKitCreateBedsRequest) async throws -> [RuntimeTestKitBed] {
        createdRequests.append(request)
        let beds: [RuntimeTestKitBed]
        if !request.roomNames.isEmpty {
            beds = request.roomNames.enumerated().map { index, roomName in
                RuntimeTestKitBed(roomName: roomName, bedID: "bed-\(index + 1)")
            }
        } else if request.appendRandomSuffix {
            let count = request.count ?? 0
            let prefix = request.prefix
            beds = (0..<count).map { index in
                RuntimeTestKitBed(roomName: "\(prefix)-\(index + 1)", bedID: "bed-\(index + 1)")
            }
        } else {
            beds = [RuntimeTestKitBed(roomName: request.prefix, bedID: "bed-1")]
        }
        status.beds = beds
        return beds
    }

    func resetTestKitBeds() async throws -> [RuntimeTestKitBed] {
        resetBedsCount += 1
        let beds = status.beds
        status.beds = []
        return beds
    }

    func deleteTestKitBeds(_ request: RuntimeTestKitDeleteBedsRequest) async throws -> [RuntimeTestKitBed] {
        deletedBedRequests.append(request)
        let requested = Set(request.roomNames)
        let deleted = status.beds.filter { requested.contains($0.roomName) }
        status.beds.removeAll { requested.contains($0.roomName) }
        return deleted
    }

    func startVirtualRecorders(_ request: RuntimeTestKitVirtualRecorderStartRequest) async throws -> RuntimeTestKitSession {
        if let startError {
            throw startError
        }
        startedRequests.append(request)
        let session = testKitSession(
            id: "session-\(startedRequests.count)",
            state: "running",
            bedRoomNames: [request.bedroomName]
        )
        status.sessions.append(session)
        status.activeSession = session
        return session
    }

    func stopVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        stoppedSessionIDs.append(sessionID)
        return session(for: sessionID, state: "stopped")
    }

    func pauseVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        pausedSessionIDs.append(sessionID)
        return session(for: sessionID, state: "paused")
    }

    func resumeVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        resumedSessionIDs.append(sessionID)
        return session(for: sessionID, state: "running")
    }

    func restartVirtualRecorders(sessionID: String?, bedroomName: String?) async throws -> RuntimeTestKitSession? {
        restartedSessionIDs.append(sessionID)
        let session = testKitSession(
            id: "session-restarted-\(restartedSessionIDs.count)",
            state: "running",
            bedRoomNames: [bedroomName ?? "TestBedroom"]
        )
        status.sessions.append(session)
        status.activeSession = session
        return session
    }

    func deleteVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        deletedSessionIDs.append(sessionID)
        let deleted = session(for: sessionID, state: "deleted")
        if let sessionID {
            status.sessions.removeAll { $0.id == sessionID }
        }
        status.activeSession = status.sessions.first
        return deleted
    }

    func deleteVirtualRecorder(vrcode: String) async throws -> RuntimeTestKitRecorderDeletion {
        deletedRecorderVRCodes.append(vrcode)
        return RuntimeTestKitRecorderDeletion(
            vrcode: vrcode,
            targetURL: "http://example.test",
            deleted: true
        )
    }

    func resetVirtualRecorders() async throws -> RuntimeTestKitStatus {
        resetSessionsCount += 1
        status.sessions = []
        status.activeSession = nil
        return status
    }

    func uploadVitalFiles(
        _ request: RuntimeTestKitVitalFileUploadRequest
    ) async throws -> RuntimeTestKitVitalFileUploadSummary {
        vitalUploadRequests.append(request)
        let bedRoomNames = try RuntimeTestKitVitalFileUploadPolicy.uniqueBedRoomNames(
            filePaths: request.filePaths
        )
        let files = request.filePaths.map { path in
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return RuntimeTestKitVitalFileUploadFileResult(
                path: path,
                filename: filename,
                bedRoomName: RuntimeTestKitVitalFileUploadPolicy.bedRoomName(filename: filename) ?? "",
                sizeBytes: 128,
                statusCode: 200,
                ok: true,
                elapsedSeconds: 0.1
            )
        }
        status.beds = bedRoomNames.enumerated().map { index, roomName in
            RuntimeTestKitBed(roomName: roomName, bedID: "bed-\(index + 1)")
        }
        return RuntimeTestKitVitalFileUploadSummary(
            files: files,
            bedRoomNames: bedRoomNames
        )
    }

    private func session(for sessionID: String?, state: String) -> RuntimeTestKitSession? {
        guard let sessionID else {
            return nil
        }
        if let existing = status.sessions.first(where: { $0.id == sessionID }) {
            return testKitSession(
                id: existing.id,
                state: state,
                bedRoomNames: existing.bedRoomNames
            )
        }
        return testKitSession(id: sessionID, state: state, bedRoomNames: ["OR-A"])
    }
}

@MainActor
private final class FakeRuntimeClient: RuntimeControlClient, RuntimeHostClient {
    let capabilities: RuntimeControlCapabilities
    var loadStatusCount = 0
    var loadHealthStatusCount = 0
    var loadRuntimeEventsCount = 0
    var lastRuntimeEventQuery: RuntimeEventQuery?
    var runtimeEventQueries: [RuntimeEventQuery] = []
    var loadVitalDBRecordersCount = 0
    var loadBackupsCount = 0
    var loadSettingsCount = 0
    var verifyUpdateBundleCount = 0
    var applySettingsCount = 0
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
    var startRuntimeServicesCount = 0
    var stopRuntimeServicesCount = 0
    var startTestKitServiceCount = 0
    var stopTestKitServiceCount = 0
    var restartTestKitServiceCount = 0
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
    var backupsToLoad: [RuntimeBackup] = []
    var redisBackupsToLoad: [RuntimeBackup] = []
    var runtimeDataBackupsToLoad: [RuntimeBackup] = []
    var lastLoadStatusSettings: RuntimeSettings?
    var lastLoadHealthStatusSettings: RuntimeSettings?
    var lastAppliedSettings: RuntimeSettings?
    var settings = RuntimeSettings()
    var status = RuntimeStatus()
    var healthStatus = RuntimeStatus()
    var vitalDBObservation: VitalDBObservationDocument?

    init(capabilities: RuntimeControlCapabilities) {
        self.capabilities = capabilities
    }

    func loadSettings() -> RuntimeSettings {
        loadSettingsCount += 1
        return settings
    }

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        loadStatusCount += 1
        lastLoadStatusSettings = settings
        return status
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
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

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory()
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

    func startRuntimeServices() async throws -> RuntimeCommandResult {
        startRuntimeServicesCount += 1
        return success()
    }

    func stopRuntimeServices() async throws -> RuntimeCommandResult {
        stopRuntimeServicesCount += 1
        return success()
    }

    func startTestKitService() async throws -> RuntimeCommandResult {
        startTestKitServiceCount += 1
        return success()
    }

    func stopTestKitService() async throws -> RuntimeCommandResult {
        stopTestKitServiceCount += 1
        return success()
    }

    func restartTestKitService() async throws -> RuntimeCommandResult {
        restartTestKitServiceCount += 1
        return success()
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
            redisBackupsPath: "/runtime/data/backups/redis",
            runtimeDataBackupsPath: "/runtime/data/backups/vitalserver-helper"
        )
    }

    private func success() -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

@MainActor
private final class FakeLocalAPISettings: RuntimeControlLocalAPISettingsApplying {
    let runtimeControlPort: Int
    var settingsWithLocalAPIPortCount = 0
    var applySettings: [RuntimeSettings] = []
    var appliedPorts: [Int] = []

    init(runtimeControlPort: Int) {
        self.runtimeControlPort = runtimeControlPort
    }

    func settingsWithLocalAPIPort(_ settings: RuntimeSettings) -> RuntimeSettings {
        settingsWithLocalAPIPortCount += 1
        var next = settings
        next.runtimeControlPort = runtimeControlPort
        return next
    }

    func apply(settings: RuntimeSettings) {
        applySettings.append(settings)
    }

    func apply(port: Int) {
        appliedPorts.append(port)
    }
}

@MainActor
private final class FakeRuntimeNativeShell: RuntimeNativeShell {
    var directoryURL: URL?
    var updateBundleURL: URL?
    var redisBackupArchiveURL: URL?
    var vitalFileURLs: [URL] = []
    var logExportDestinationURL: URL?
    var logExportDestinationValidationMessages: [String: String] = [:]
    var chooseDirectoryPrompts: [String] = []
    var chooseUpdateBundlePrompts: [String] = []
    var chooseRedisBackupArchivePrompts: [String] = []
    var chooseVitalFilesPrompts: [String] = []
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

    func chooseVitalFiles(prompt: String) -> [URL] {
        chooseVitalFilesPrompts.append(prompt)
        return vitalFileURLs
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

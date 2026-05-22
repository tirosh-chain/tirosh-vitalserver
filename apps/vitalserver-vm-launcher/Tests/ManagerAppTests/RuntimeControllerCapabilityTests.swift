import Foundation
@testable import ManagerApp
import XCTest

@MainActor
final class RuntimeControllerCapabilityTests: XCTestCase {
    func testRestrictedClientPreventsLocalOnlyOperations() async {
        let client = FakeRuntimeClient(capabilities: .restricted)
        let nativeShell = FakeRuntimeNativeShell()
        let controller = RuntimeController(
            runtimeClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )
        controller.selectedBundleURL = URL(fileURLWithPath: "/bundle")
        controller.selectedBundleVerified = true
        controller.selectedBackupURL = URL(fileURLWithPath: "/backup")

        controller.chooseVitalFilesDirectory()
        await controller.chooseUpdateBundle()
        await controller.applySettings()
        await controller.verifySelectedBundle()
        await controller.applySelectedBundle()
        await controller.rollbackRuntime()
        await controller.deleteSelectedBackup()
        await controller.repairProxyPort()
        await controller.repairDatastore()
        await controller.startRuntimeServices()
        await controller.stopRuntimeServices()
        await controller.exportLogs()
        controller.openLogs()
        controller.openVitalFilesDirectory()

        XCTAssertEqual(client.applySettingsCount, 0)
        XCTAssertEqual(client.verifyUpdateBundleCount, 0)
        XCTAssertEqual(client.applyUpdateBundleCount, 0)
        XCTAssertEqual(client.rollbackRuntimeCount, 0)
        XCTAssertEqual(client.deleteBackupCount, 0)
        XCTAssertEqual(client.repairProxyCount, 0)
        XCTAssertEqual(client.repairDatastoreCount, 0)
        XCTAssertEqual(client.startRuntimeServicesCount, 0)
        XCTAssertEqual(client.stopRuntimeServicesCount, 0)
        XCTAssertEqual(client.exportLogsCount, 0)
        XCTAssertEqual(client.preferredLogsPathCount, 0)
        XCTAssertEqual(client.createDirectoryURLs, [])
        XCTAssertEqual(nativeShell.chooseDirectoryCount, 0)
        XCTAssertEqual(nativeShell.chooseUpdateBundleCount, 0)
        XCTAssertEqual(nativeShell.chooseLogExportDestinationCount, 0)
        XCTAssertEqual(nativeShell.openedFileURLs, [])
        XCTAssertEqual(controller.message, AppConstants.StatusText.actionUnavailable)
    }

    func testRefreshSkipsReleaseMetadataWhenCapabilityIsUnavailable() async {
        var capabilities = RuntimeClientCapabilities.restricted
        capabilities.canStreamLogs = false
        let client = FakeRuntimeClient(capabilities: capabilities)
        let controller = RuntimeController(runtimeClient: client, healthNotifications: NoopHealthNotifications())
        controller.logStreaming = false

        await controller.refresh()

        XCTAssertEqual(client.loadReleaseInfoCount, 0)
        XCTAssertEqual(client.loadStatusCount, 1)
        XCTAssertEqual(client.loadBackupsCount, 1)
        XCTAssertEqual(controller.releaseInfo, .generated)
    }

    func testNativeShellProvidesDirectorySelectionWithoutLeakingPanelDetailsToController() {
        let client = FakeRuntimeClient(capabilities: RuntimeClientCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        nativeShell.directoryURL = URL(fileURLWithPath: "/Users/test/Vital Files")
        let controller = RuntimeController(
            runtimeClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        controller.chooseVitalFilesDirectory()

        XCTAssertEqual(nativeShell.chooseDirectoryPrompts, [AppConstants.Actions.chooseDirectory])
        XCTAssertEqual(client.createDirectoryURLs, [URL(fileURLWithPath: "/Users/test/Vital Files")])
        XCTAssertEqual(controller.settings.vitalFilesDirectory, "/Users/test/Vital Files")
    }

    func testNativeShellProvidesUpdateBundleURLAndClientVerifiesSelectedBundle() async {
        let client = FakeRuntimeClient(capabilities: RuntimeClientCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let bundleURL = URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")
        nativeShell.updateBundleURL = bundleURL
        let controller = RuntimeController(
            runtimeClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        await controller.chooseUpdateBundle()

        XCTAssertEqual(nativeShell.chooseUpdateBundlePrompts, [AppConstants.Actions.chooseBundle])
        XCTAssertEqual(controller.selectedBundleURL, bundleURL)
        XCTAssertEqual(controller.selectedBundleSummary, "bundle: /tmp/update-bundle.tar.gz")
        XCTAssertEqual(client.verifiedBundleURLs, [bundleURL])
        XCTAssertTrue(controller.selectedBundleVerified)
    }

    func testOpenAndExportOperationsUseNativeShellBoundary() async {
        let client = FakeRuntimeClient(capabilities: RuntimeClientCapabilities())
        let nativeShell = FakeRuntimeNativeShell()
        let exportURL = URL(fileURLWithPath: "/tmp/vitalserver-logs.zip")
        nativeShell.logExportDestinationURL = exportURL
        let controller = RuntimeController(
            runtimeClient: client,
            healthNotifications: NoopHealthNotifications(),
            nativeShell: nativeShell
        )

        controller.openLogs()
        controller.openVitalServer()
        await controller.exportLogs()

        XCTAssertEqual(nativeShell.openedFileURLs, [URL(fileURLWithPath: "/logs")])
        XCTAssertEqual(nativeShell.openedWebURLs, [URL(string: AppConstants.Product.vitalServerURL(proxyPort: controller.status.proxyPort))])
        XCTAssertEqual(nativeShell.chooseLogExportDestinationPrompts, [AppConstants.Actions.exportLogs])
        XCTAssertEqual(client.exportLogDestinationURLs, [exportURL])
    }
}

private extension RuntimeClientCapabilities {
    static var restricted: RuntimeClientCapabilities {
        RuntimeClientCapabilities(
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

private struct NoopHealthNotifications: HealthNotifying {
    func configure() {}
    func notify(title: String, body: String) {}
}

@MainActor
private final class FakeRuntimeClient: RuntimeClient {
    let capabilities: RuntimeClientCapabilities
    var loadStatusCount = 0
    var loadBackupsCount = 0
    var verifyUpdateBundleCount = 0
    var applySettingsCount = 0
    var applyUpdateBundleCount = 0
    var rollbackRuntimeCount = 0
    var deleteBackupCount = 0
    var repairProxyCount = 0
    var repairDatastoreCount = 0
    var startRuntimeServicesCount = 0
    var stopRuntimeServicesCount = 0
    var exportLogsCount = 0
    var loadReleaseInfoCount = 0
    var preferredLogsPathCount = 0
    var createDirectoryURLs: [URL] = []
    var verifiedBundleURLs: [URL] = []
    var exportLogDestinationURLs: [URL] = []

    init(capabilities: RuntimeClientCapabilities) {
        self.capabilities = capabilities
    }

    func loadSettings() -> RuntimeSettings {
        RuntimeSettings()
    }

    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        loadStatusCount += 1
        return RuntimeStatus()
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        RuntimeStatus()
    }

    func loadBackups(latestBackupPath: String?) -> [RuntimeBackup] {
        loadBackupsCount += 1
        return []
    }

    func updateBundleSummary(url: URL) -> String {
        "bundle: \(url.path)"
    }

    func logText(sourceID: LogSourceID, helperMessage: String, lineLimit: Int) -> String {
        helperMessage
    }

    func preferredLogsPath() -> String {
        preferredLogsPathCount += 1
        return "/logs"
    }

    func vitalFileFolders(root: String) -> [VitalFileFolder] {
        []
    }

    func legacyCommandProgressLine() -> String? {
        nil
    }

    func createDirectory(at url: URL) {
        createDirectoryURLs.append(url)
    }

    func verifyUpdateBundle(url: URL) async throws -> ProcessResult {
        verifyUpdateBundleCount += 1
        verifiedBundleURLs.append(url)
        return success()
    }

    func uninstallRuntime(clean: Bool) async throws -> ProcessResult {
        success()
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> ProcessResult {
        applySettingsCount += 1
        return success()
    }

    func applyUpdateBundle(url: URL) async throws -> ProcessResult {
        applyUpdateBundleCount += 1
        return success()
    }

    func rollbackRuntime(backupURL: URL) async throws -> ProcessResult {
        rollbackRuntimeCount += 1
        return success()
    }

    func deleteBackup(url: URL) async throws -> ProcessResult {
        deleteBackupCount += 1
        return success()
    }

    func repairProxy(proxyPort: Int) async throws -> ProcessResult {
        repairProxyCount += 1
        return success()
    }

    func repairDatastore() async throws -> ProcessResult {
        repairDatastoreCount += 1
        return success()
    }

    func startRuntimeServices() async throws -> ProcessResult {
        startRuntimeServicesCount += 1
        return success()
    }

    func stopRuntimeServices() async throws -> ProcessResult {
        stopRuntimeServicesCount += 1
        return success()
    }

    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        exportLogsCount += 1
        exportLogDestinationURLs.append(destination)
        return RuntimeLogExportResult(destination: destination)
    }

    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        loadReleaseInfoCount += 1
        return RuntimeReleaseInfo(
            helperVersion: "test",
            minimumUpdaterVersion: "test",
            vitalServerVersion: "test",
            services: []
        )
    }

    private func success() -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

@MainActor
private final class FakeRuntimeNativeShell: RuntimeNativeShell {
    var directoryURL: URL?
    var updateBundleURL: URL?
    var logExportDestinationURL: URL?
    var chooseDirectoryPrompts: [String] = []
    var chooseUpdateBundlePrompts: [String] = []
    var chooseLogExportDestinationPrompts: [String] = []
    var openedFileURLs: [URL] = []
    var openedWebURLs: [URL] = []
    var relaunchHelperCount = 0
    var terminateCount = 0

    var chooseDirectoryCount: Int {
        chooseDirectoryPrompts.count
    }

    var chooseUpdateBundleCount: Int {
        chooseUpdateBundlePrompts.count
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

    func chooseLogExportDestination(defaultName: String, prompt: String) -> URL? {
        chooseLogExportDestinationPrompts.append(prompt)
        return logExportDestinationURL
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

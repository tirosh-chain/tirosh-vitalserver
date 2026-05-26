import Foundation
import Contracts
import Core
import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

@MainActor
final class RuntimeViewModelCapabilityTests: XCTestCase {
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

        viewModel.chooseVitalFilesDirectory()
        await viewModel.chooseUpdateBundle()
        await viewModel.applySettings()
        await viewModel.verifySelectedBundle()
        await viewModel.applySelectedBundle()
        await viewModel.rollbackRuntime()
        await viewModel.deleteSelectedBackup()
        await viewModel.repairProxyPort()
        await viewModel.repairDatastore()
        await viewModel.createRedisBackup()
        await viewModel.startRuntimeServices()
        await viewModel.stopRuntimeServices()
        await viewModel.exportLogs()
        viewModel.openLogs()
        viewModel.openBackups()
        viewModel.openRedisBackups()
        viewModel.openVitalFilesDirectory()

        XCTAssertEqual(client.applySettingsCount, 0)
        XCTAssertEqual(client.verifyUpdateBundleCount, 0)
        XCTAssertEqual(client.applyUpdateBundleCount, 0)
        XCTAssertEqual(client.rollbackRuntimeCount, 0)
        XCTAssertEqual(client.deleteBackupCount, 0)
        XCTAssertEqual(client.repairProxyCount, 0)
        XCTAssertEqual(client.repairDatastoreCount, 0)
        XCTAssertEqual(client.createRedisBackupCount, 0)
        XCTAssertEqual(client.startRuntimeServicesCount, 0)
        XCTAssertEqual(client.stopRuntimeServicesCount, 0)
        XCTAssertEqual(client.exportLogsCount, 0)
        XCTAssertEqual(client.preferredLogsPathCount, 0)
        XCTAssertEqual(client.createDirectoryURLs, [])
        XCTAssertEqual(nativeShell.chooseDirectoryCount, 0)
        XCTAssertEqual(nativeShell.chooseUpdateBundleCount, 0)
        XCTAssertEqual(nativeShell.chooseLogExportDestinationCount, 0)
        XCTAssertEqual(nativeShell.openedFileURLs, [])
        XCTAssertEqual(viewModel.message, AppConstants.StatusText.actionUnavailable)
    }

    func testRefreshSkipsReleaseMetadataWhenCapabilityIsUnavailable() async {
        var capabilities = RuntimeControlCapabilities.restricted
        capabilities.canStreamLogs = false
        let client = FakeRuntimeClient(capabilities: capabilities)
        let viewModel = RuntimeViewModel(controlClient: client, hostClient: client, healthNotifications: NoopHealthNotifications())
        viewModel.logStreaming = false

        await viewModel.refresh()

        XCTAssertEqual(client.loadReleaseInfoCount, 0)
        XCTAssertEqual(client.loadStatusCount, 1)
        XCTAssertEqual(client.loadBackupsCount, 1)
        XCTAssertEqual(viewModel.releaseInfo, .generated)
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
        XCTAssertEqual(client.createDirectoryURLs, [URL(fileURLWithPath: "/Users/test/Vital Files")])
        XCTAssertEqual(viewModel.settings.vitalFilesDirectory, "/Users/test/Vital Files")
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
        viewModel.openVitalServer()
        viewModel.openVitalDBWebsite()
        await viewModel.exportLogs()

        XCTAssertEqual(nativeShell.openedFileURLs, [
            URL(fileURLWithPath: "/logs"),
            URL(fileURLWithPath: "/backups"),
            URL(fileURLWithPath: "/backups/redis"),
        ])
        XCTAssertEqual(nativeShell.openedWebURLs, [
            URL(string: AppConstants.Product.vitalServerURL(proxyPort: viewModel.status.proxyPort)),
            URL(string: AppConstants.Product.vitalDBURL),
        ])
        XCTAssertEqual(nativeShell.chooseLogExportDestinationPrompts, [AppConstants.Actions.exportLogs])
        XCTAssertEqual(client.exportLogDestinationURLs, [exportURL])
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

        viewModel.chooseVitalFilesDirectory()
        await viewModel.refresh()

        XCTAssertEqual(controlClient.loadStatusCount, 1)
        XCTAssertEqual(controlClient.createDirectoryURLs, [])
        XCTAssertEqual(hostClient.createDirectoryURLs, [URL(fileURLWithPath: "/Users/test/Vital Files")])
        XCTAssertEqual(hostClient.loadBackupsCount, 1)
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

private struct NoopHealthNotifications: HealthNotifying {
    func configure() {}
    func notify(title: String, body: String) {}
}

@MainActor
private final class FakeRuntimeClient: RuntimeControlClient, RuntimeHostClient {
    let capabilities: RuntimeControlCapabilities
    var loadStatusCount = 0
    var loadBackupsCount = 0
    var verifyUpdateBundleCount = 0
    var applySettingsCount = 0
    var applyUpdateBundleCount = 0
    var rollbackRuntimeCount = 0
    var deleteBackupCount = 0
    var repairProxyCount = 0
    var repairDatastoreCount = 0
    var createRedisBackupCount = 0
    var startRuntimeServicesCount = 0
    var stopRuntimeServicesCount = 0
    var exportLogsCount = 0
    var loadReleaseInfoCount = 0
    var preferredLogsPathCount = 0
    var createDirectoryURLs: [URL] = []
    var verifiedBundleURLs: [URL] = []
    var exportLogDestinationURLs: [URL] = []

    init(capabilities: RuntimeControlCapabilities) {
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

    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [])
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [])
    }

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        nil
    }

    func loadBackups(latestBackupPath: String?) -> [RuntimeBackup] {
        loadBackupsCount += 1
        return []
    }

    func loadRedisBackups() -> [RuntimeBackup] {
        []
    }

    func updateBundleSummary(url: URL) -> String {
        "bundle: \(url.path)"
    }

    func logText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) -> String {
        helperMessage
    }

    func loadLogText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) async -> String {
        logText(sourceID: sourceID, helperMessage: helperMessage, lineLimit: lineLimit)
    }

    func preferredLogsPath() -> String {
        preferredLogsPathCount += 1
        return "/logs"
    }

    func vitalFileFolders(root: String) -> [VitalFilesFolder] {
        []
    }

    func legacyCommandProgressLine() -> String? {
        nil
    }

    func createDirectory(at url: URL) {
        createDirectoryURLs.append(url)
    }

    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        verifyUpdateBundleCount += 1
        verifiedBundleURLs.append(url)
        return success()
    }

    func uninstallRuntime(clean: Bool) async throws -> RuntimeCommandResult {
        success()
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult {
        applySettingsCount += 1
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

    func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        deleteBackupCount += 1
        return success()
    }

    func repairProxy(proxyPort: Int) async throws -> RuntimeCommandResult {
        repairProxyCount += 1
        return success()
    }

    func repairDatastore() async throws -> RuntimeCommandResult {
        repairDatastoreCount += 1
        return success()
    }

    func createRedisBackup() async throws -> RuntimeCommandResult {
        createRedisBackupCount += 1
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

    func loadInstallInfo() -> RuntimeInstallInfo {
        RuntimeInstallInfo(runtimeHomePath: "/runtime", backupsPath: "/backups")
    }

    private func success() -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
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
    var existingDirectories: Set<String>?
    var confirmCreateDirectoryResponses: [Bool] = []
    var confirmCreateDirectoryPaths: [String] = []
    var createdDirectoryURLs: [URL] = []
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

    func directoryExists(_ url: URL) -> Bool {
        existingDirectories?.contains(url.path) ?? true
    }

    func confirmCreateDirectory(path: String) -> Bool {
        confirmCreateDirectoryPaths.append(path)
        return confirmCreateDirectoryResponses.isEmpty ? false : confirmCreateDirectoryResponses.removeFirst()
    }

    func createDirectory(_ url: URL) throws {
        createdDirectoryURLs.append(url)
        existingDirectories?.insert(url.path)
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

import Foundation
@testable import ManagerApp
import XCTest

@MainActor
final class RuntimeControllerCapabilityTests: XCTestCase {
    func testRestrictedClientPreventsLocalOnlyOperations() async {
        let client = FakeRuntimeClient(capabilities: .restricted)
        let controller = RuntimeController(runtimeClient: client, healthNotifications: NoopHealthNotifications())
        controller.selectedBundlePath = "/bundle"
        controller.selectedBundleVerified = true
        controller.selectedBackupPath = "/backup"

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
        "bundle"
    }

    func logText(sourceID: String, helperMessage: String, lineLimit: Int) -> String {
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

    func createDirectory(at url: URL) {}

    func verifyUpdateBundle(path: String) async throws -> ProcessResult {
        verifyUpdateBundleCount += 1
        return success()
    }

    func uninstallRuntime(clean: Bool) async throws -> ProcessResult {
        success()
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> ProcessResult {
        applySettingsCount += 1
        return success()
    }

    func applyUpdateBundle(path: String) async throws -> ProcessResult {
        applyUpdateBundleCount += 1
        return success()
    }

    func rollbackRuntime(backupPath: String) async throws -> ProcessResult {
        rollbackRuntimeCount += 1
        return success()
    }

    func deleteBackup(path: String) async throws -> ProcessResult {
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

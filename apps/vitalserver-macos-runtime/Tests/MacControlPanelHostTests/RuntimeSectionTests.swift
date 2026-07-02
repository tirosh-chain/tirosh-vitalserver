@testable import MacControlPanelHost
import Contracts
import Foundation
import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters
@testable import OutboundAdapters

final class RuntimeSectionTests: XCTestCase {
    func testStableRuntimeSectionsShowProductLab() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: false).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionRecorders,
            AppConstants.Labels.sectionBeds,
            AppConstants.Labels.sectionLab,
            AppConstants.Labels.sectionObservability,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionDangerZone,
        ])
    }

    func testTestEnabledRuntimeSectionsKeepSameProductNavigation() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: true).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionRecorders,
            AppConstants.Labels.sectionBeds,
            AppConstants.Labels.sectionLab,
            AppConstants.Labels.sectionObservability,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionDangerZone,
        ])
    }

    func testRuntimeSectionsExposePrimaryUtilityAndOverflowGroups() {
        XCTAssertEqual(RuntimeSection.primarySections(testEnabled: true), [
            .status,
            .recorders,
            .beds,
            .lab,
            .settings,
            .update,
        ])
        XCTAssertEqual(RuntimeSection.utilitySections(testEnabled: true), [.advanced])
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: true), [.observability, .log, .info, .dangerZone])
    }

    func testStableRuntimeSectionOverflowMovesDiagnosticsOutOfPrimaryNavigation() {
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: false), [.observability, .log, .info, .dangerZone])
        XCTAssertTrue(RuntimeSection.sectionIsInOverflow(.dangerZone, testEnabled: false))
        XCTAssertFalse(RuntimeSection.sectionIsInOverflow(.advanced, testEnabled: false))
    }

    func testRecoverySectionsRefreshBackupListsWhileSelected() {
        XCTAssertTrue(RuntimeSection.advanced.refreshesBackupListsWhileSelected)
        XCTAssertTrue(RuntimeSection.dangerZone.refreshesBackupListsWhileSelected)
        XCTAssertFalse(RuntimeSection.status.refreshesBackupListsWhileSelected)
        XCTAssertFalse(RuntimeSection.update.refreshesBackupListsWhileSelected)
    }

    @MainActor
    func testRuntimeControlDevConsoleURLUsesLocalAPI() {
        XCTAssertEqual(
            RuntimeControlLocalAPIConstants.devConsoleURL,
            "http://127.0.0.1:18321/dev/runtime-control"
        )
        XCTAssertEqual(
            RuntimeControlLocalAPIConstants.pwaURL,
            "http://127.0.0.1:18321/"
        )
    }

    @MainActor
    func testRuntimeControlLocalAPISettingsPersistConfiguredPort() {
        let store = InMemoryRuntimeControlLocalAPISettingsStore()
        let coordinator = RuntimeControlLocalAPISettingsCoordinator(store: store)
        var changedPorts: [Int] = []
        coordinator.onPortChanged = { changedPorts.append($0) }

        coordinator.apply(port: 18_444)
        let settings = coordinator.settingsWithLocalAPIPort(RuntimeSettings())

        XCTAssertEqual(store.runtimeControlPort, 18_444)
        XCTAssertEqual(settings.runtimeControlPort, 18_444)
        XCTAssertEqual(changedPorts, [18_444])
    }

    @MainActor
    func testRuntimeControlAPIHandlerAppliesLocalAPISettingsOnlyAfterSuccessfulApply() async throws {
        let client = HostFakeRuntimeControlClient()
        let store = InMemoryRuntimeControlLocalAPISettingsStore(runtimeControlPort: 18_321)
        let handler = makeRuntimeControlAPIHandler(client: client, localAPISettingsStore: store)
        var settings = RuntimeSettings(cpuCount: 4, memoryGiB: 8)
        settings.runtimeControlPort = 18_444

        let response = try await handler.applySettings(settings)

        XCTAssertEqual(response.result.exitCode, 0)
        XCTAssertEqual(store.runtimeControlPort, 18_444)
    }

    @MainActor
    func testRuntimeControlAPIHandlerDoesNotApplyLocalAPISettingsAfterFailedApply() async throws {
        let client = HostFakeRuntimeControlClient()
        client.applySettingsResult = RuntimeCommandResult(
            exitCode: 2,
            stdout: "",
            stderr: "Advertised URLs must be absolute http/https URLs."
        )
        let store = InMemoryRuntimeControlLocalAPISettingsStore(runtimeControlPort: 18_321)
        let handler = makeRuntimeControlAPIHandler(client: client, localAPISettingsStore: store)
        var settings = RuntimeSettings(cpuCount: 4, memoryGiB: 8)
        settings.runtimeControlPort = 18_444

        let response = try await handler.applySettings(settings)

        XCTAssertEqual(response.result.exitCode, 2)
        XCTAssertEqual(response.result.stderr, "Advertised URLs must be absolute http/https URLs.")
        XCTAssertEqual(store.runtimeControlPort, 18_321)
    }

    @MainActor
    func testRuntimeControlAPIServerIsIndependentFromDevConsole() {
        XCTAssertTrue(MacRuntimeControlEnvironment.shouldStartRuntimeControlAPIServer())
        XCTAssertFalse(MacRuntimeControlEnvironment.shouldServeRuntimeControlDevConsole(testEnabled: false))
        XCTAssertTrue(MacRuntimeControlEnvironment.shouldServeRuntimeControlDevConsole(testEnabled: true))
    }

    @MainActor
    private func makeRuntimeControlAPIHandler(
        client: HostFakeRuntimeControlClient,
        localAPISettingsStore: InMemoryRuntimeControlLocalAPISettingsStore
    ) -> MacRuntimeControlAPIHandler {
        MacRuntimeControlAPIHandler(
            commandClient: client,
            hostClient: client,
            readWorker: MacRuntimeControlReadWorker(
                releaseInfo: RuntimeReleaseInfo(
                    helperVersion: "helper",
                    minimumUpdaterVersion: "1",
                    vitalServerVersion: "runtime",
                    services: []
                ),
                statusReader: HostStubStatusReader(),
                observabilityReader: HostStubObservabilityReader(),
                fileReader: HostStubFileReader(),
                settingsReader: HostStubSettingsReader()
            ),
            localAPISettings: RuntimeControlLocalAPISettingsCoordinator(store: localAPISettingsStore)
        )
    }
}

@MainActor
private final class HostFakeRuntimeControlClient: RuntimeControlClient, RuntimeHostClient {
    var capabilities = RuntimeControlCapabilities(canOpenLocalFiles: false)
    var applySettingsResult = RuntimeCommandResult(exitCode: 0, stdout: "settings applied", stderr: "")

    func loadSettings() -> RuntimeSettings { RuntimeSettings() }
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus { RuntimeStatus() }
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus { RuntimeStatus() }
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.fromOptional(nil)
    }
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory { RuntimeVitalRecorderHistory(observations: []) }
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory { RuntimeVitalRelationshipHistory() }
    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "uninstall", stderr: "")
    }
    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult { applySettingsResult }
    func repairProxy() async throws -> RuntimeCommandResult { RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "") }
    func repairDatastore() async throws -> RuntimeCommandResult { RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "") }
    func repairVMDisk() async throws -> RuntimeCommandResult { RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "") }
    func repairRuntimeServices() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func createRedisBackup() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        RuntimeReleaseInfo(helperVersion: "helper", minimumUpdaterVersion: "1", vitalServerVersion: "runtime", services: [])
    }
    func loadInstallInfo() -> RuntimeInstallInfo { RuntimeInstallInfo() }
    func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup] { [] }
    func loadRedisBackups() throws -> [RuntimeBackup] { [] }
    func loadRuntimeDataBackups() throws -> [RuntimeBackup] { [] }
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult { .loaded("") }
    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult { .loaded("") }
    func loadLogTextResult(sourceID: RuntimeLogSource, lineLimit: Int) async -> RuntimeHostTextReadResult { .loaded("") }
    func preferredLogsPath() -> String { "/logs" }
    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] { [] }
    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func restoreRedisBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func createRuntimeDataBackup() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func restoreRuntimeDataBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        RuntimeLogExportResult(destination: destination)
    }
}

private struct HostStubSettingsReader: RuntimeSettingsReading {
    func load() -> RuntimeSettings { RuntimeSettings() }
}

private struct HostStubStatusReader: RuntimeStatusReading {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus { RuntimeStatus() }
    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus { RuntimeStatus() }
}

private struct HostStubObservabilityReader: RuntimeObservabilityReading {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.fromOptional(nil)
    }
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory { RuntimeVitalRecorderHistory(observations: []) }
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory { RuntimeVitalRelationshipHistory() }
}

private struct HostStubFileReader: RuntimeHostFileReading {
    func backups(latestBackupPath: String?) throws -> [RuntimeBackup] { [] }
    func redisBackups() throws -> [RuntimeBackup] { [] }
    func runtimeDataBackups() throws -> [RuntimeBackup] { [] }
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult { .loaded("") }
    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult { .loaded("") }
    func preferredLogsPath() -> String { "/logs" }
    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] { [] }
}

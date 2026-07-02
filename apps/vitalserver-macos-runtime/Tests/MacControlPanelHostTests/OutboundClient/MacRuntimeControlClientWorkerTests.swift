import Application
import Contracts
import Foundation
import RuntimeControl
@testable import OutboundAdapters
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class MacRuntimeControlClientWorkerTests: XCTestCase {
    func testReadWorkerDelegatesReadModelsToInjectedReaders() async throws {
        let statusReader = AdapterStubStatusReader()
        let observabilityReader = AdapterStubObservabilityReader()
        let fileReader = AdapterStubFileReader()
        let settingsReader = AdapterStubSettingsReader()
        let worker = MacRuntimeControlReadWorker(
            releaseInfo: RuntimeReleaseInfo(
                helperVersion: "helper",
                minimumUpdaterVersion: "1",
                vitalServerVersion: "runtime",
                services: []
            ),
            statusReader: statusReader,
            observabilityReader: observabilityReader,
            fileReader: fileReader,
            settingsReader: settingsReader
        )

        let settings = await worker.loadSettings()
        let status = await worker.loadStatus(settings: settings)
        let health = await worker.loadHealthStatus(settings: settings)
        let limitedEvents = await worker.loadRuntimeEvents(limit: 5)
        let queriedEvents = await worker.loadRuntimeEvents(query: RuntimeEventQuery(limit: 7))
        let snapshot = await worker.loadVitalDBObservationSnapshot()
        let recorders = await worker.loadVitalDBRecorders()
        let relationships = await worker.loadVitalDBRelationships()
        let backups = try await worker.loadBackups(latestBackupPath: "/backup/latest")
        let redisBackups = try await worker.loadRedisBackups()
        let summary = await worker.updateBundleSummaryResult(url: URL(fileURLWithPath: "/bundle"))
        let folders = try await worker.vitalFileFolders(root: "/vital")
        let releaseInfo = await worker.loadReleaseInfo()
        let installInfo = await worker.loadInstallInfo()

        XCTAssertEqual(settings.proxyPort, 19080)
        XCTAssertEqual(status.statusMessage, "status")
        XCTAssertEqual(health.statusMessage, "health")
        XCTAssertEqual(limitedEvents.matchingCount, 5)
        XCTAssertEqual(queriedEvents.matchingCount, 7)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-30T00:00:00Z")
        XCTAssertEqual(recorders.recorders.count, 0)
        XCTAssertEqual(relationships.readError, "relationships")
        XCTAssertEqual(backups.map(\.path), ["/backup/latest"])
        XCTAssertEqual(redisBackups.map(\.path), ["/redis/latest"])
        XCTAssertEqual(summary, .loaded("summary:/bundle"))
        XCTAssertEqual(folders.map(\.path), ["/vital"])
        XCTAssertEqual(releaseInfo.helperVersion, "helper")
        XCTAssertFalse(installInfo.runtimeHomePath?.isEmpty ?? true)
    }

    func testClientDelegatesReadsAndCommandsToWorkers() async throws {
        let runner = AdapterFakePrivilegedCommandRunner()
        let environment = AdapterFakeActionEnvironment()
        let exporter = AdapterFakeLogExporter()
        let commandWorker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: runner,
            actionEnvironment: environment,
            logExporter: exporter,
            guestMaintenanceController: AdapterFakeGuestMaintenanceController(),
            guestControlBaseURLOverride: "http://127.0.0.1:18330"
        )
        let releaseInfo = RuntimeReleaseInfo(
            helperVersion: "helper",
            minimumUpdaterVersion: "1",
            vitalServerVersion: "runtime",
            services: []
        )
        let client = MacRuntimeControlClient(
            releaseInfo: releaseInfo,
            statusReader: AdapterStubStatusReader(),
            observabilityReader: AdapterStubObservabilityReader(),
            fileReader: AdapterStubFileReader(),
            settingsReader: AdapterStubSettingsReader(),
            commandWorker: commandWorker
        )

        let healthStatus = await client.loadHealthStatus(settings: RuntimeSettings())
        let verification = try await client.verifyUpdateBundle(url: URL(fileURLWithPath: "/bundle"))
        let export = try await client.exportLogs(to: URL(fileURLWithPath: "/tmp/logs.zip"))
        let loadedReleaseInfo = try await client.loadReleaseInfo()

        XCTAssertEqual(client.loadSettings().proxyPort, 19080)
        XCTAssertEqual(client.loadStatus(settings: RuntimeSettings()).statusMessage, "status")
        XCTAssertEqual(healthStatus.statusMessage, "health")
        XCTAssertEqual(client.loadRuntimeEvents(limit: 3).matchingCount, 3)
        XCTAssertEqual(client.loadRuntimeEvents(query: RuntimeEventQuery(limit: 4)).matchingCount, 4)
        XCTAssertNotNil(client.loadVitalDBObservationSnapshot().observation)
        XCTAssertEqual(client.loadVitalDBRecorders().recorders.count, 0)
        XCTAssertEqual(client.loadVitalDBRelationships().readError, "relationships")
        let backups = try client.loadBackups(latestBackupPath: "/backup/latest")
        let redisBackups = try client.loadRedisBackups()
        let folders = try client.vitalFileFolders(root: "/vital")
        let asyncLogText = await client.loadLogTextResult(sourceID: RuntimeLogSource.command, lineLimit: 11)
        XCTAssertEqual(backups.map { $0.path }, ["/backup/latest"])
        XCTAssertEqual(redisBackups.map { $0.path }, ["/redis/latest"])
        XCTAssertEqual(client.updateBundleSummaryResult(url: URL(fileURLWithPath: "/bundle")), .loaded("summary:/bundle"))
        XCTAssertEqual(client.logTextResult(sourceID: RuntimeLogSource.command, lineLimit: 10), .loaded("log:command:10"))
        XCTAssertEqual(asyncLogText, .loaded("log:command:11"))
        XCTAssertEqual(client.preferredLogsPath(), "/logs")
        XCTAssertEqual(folders.map { $0.name }, ["vital"])
        XCTAssertEqual(verification.stdout, "verified:/bundle")
        XCTAssertEqual(export.destination.path, "/tmp/logs.zip")
        XCTAssertEqual(loadedReleaseInfo, releaseInfo)
        XCTAssertFalse(client.loadInstallInfo().appBundlePath?.isEmpty ?? true)

        _ = try await client.uninstallRuntime(mode: .clean)
        var settings = RuntimeSettings()
        settings.changeAdminPassword = true
        settings.adminPassword = "secret"
        _ = try await client.applySettings(settings)
        _ = try await client.applyUpdateBundle(url: URL(fileURLWithPath: "/bundle"))
        _ = try await client.rollbackRuntime(backupURL: URL(fileURLWithPath: "/backup"))
        _ = try await client.restoreRedisBackup(backupURL: URL(fileURLWithPath: "/redis/latest"))
        _ = try await client.deleteBackup(
            url: URL(fileURLWithPath: "\(RuntimeControlClientConstants.Paths.backups)/20260522-before-0.1.3")
        )
        _ = try await client.repairProxy()
        _ = try await client.repairDatastore()
        _ = try await client.repairVMDisk()
        _ = try await client.repairRuntimeServices()
        _ = try await client.createRedisBackup()

        XCTAssertEqual(environment.removedTemporaryFiles.map(\.path), [
            "/tmp/admin-password",
            "/tmp/recorder-ingress-settings.json",
            "/tmp/redis-relay-settings.json",
        ])
        XCTAssertEqual(runner.shellCommands.count, 8)
        XCTAssertTrue(runner.shellCommands.contains { $0.contains("--clean") })
        XCTAssertFalse(runner.shellCommands.contains { $0.contains("--force-clean-uninstaller") })
        XCTAssertTrue(runner.shellCommands.contains { $0.contains("--admin-password-file") })
    }

    func testApplySettingsReportsAdminPasswordCleanupFailureAsOutputIssue() async throws {
        let environment = AdapterFakeActionEnvironment()
        environment.removeError = CocoaError(.fileWriteNoPermission)
        environment.removeErrorPaths = ["/tmp/admin-password"]
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: environment,
            logExporter: AdapterFakeLogExporter()
        )
        var settings = RuntimeSettings()
        settings.changeAdminPassword = true
        settings.adminPassword = "secret"

        let result = try await worker.applySettings(settings)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(environment.removedTemporaryFiles.map(\.path), [
            "/tmp/admin-password",
            "/tmp/recorder-ingress-settings.json",
            "/tmp/redis-relay-settings.json",
        ])
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertEqual(result.outputIssues.first?.stream, .stderr)
        XCTAssertTrue(result.outputIssues.first?.message.contains("admin password file cleanup failed") == true)
        XCTAssertTrue(result.outputIssues.first?.message.contains("/tmp/admin-password") == true)
    }

    func testApplySettingsCleansPreparedTemporaryFilesWhenLaterPreparationFails() async throws {
        let environment = AdapterFakeActionEnvironment()
        environment.redisRelaySettingsWriteError = CocoaError(.fileWriteNoPermission)
        let runner = AdapterFakePrivilegedCommandRunner()
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: runner,
            actionEnvironment: environment,
            logExporter: AdapterFakeLogExporter()
        )
        var settings = RuntimeSettings()
        settings.changeAdminPassword = true
        settings.adminPassword = "secret"

        do {
            _ = try await worker.applySettings(settings)
            XCTFail("Expected Redis relay settings file preparation failure")
        } catch {
            XCTAssertEqual(runner.shellCommands, [])
            XCTAssertEqual(environment.removedTemporaryFiles.map(\.path), [
                "/tmp/admin-password",
                "/tmp/recorder-ingress-settings.json",
            ])
        }
    }

    func testCommandWorkerReportsMissingExecutableBoundaries() async {
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: AdapterFakeActionEnvironment(executableStates: [
                RuntimeControlClientConstants.Paths.launcher: .missing,
                RuntimeControlClientConstants.Paths.uninstaller: .missing,
            ]),
            logExporter: AdapterFakeLogExporter()
        )

        do {
            _ = try await worker.verifyUpdateBundle(url: URL(fileURLWithPath: "/bundle"))
            XCTFail("Expected missing launcher")
        } catch {
            XCTAssertEqual((error as? RuntimeClientError)?.errorDescription, RuntimeControlClientConstants.StatusText.missingLauncher)
        }
        do {
            _ = try await worker.uninstallRuntime(mode: .standard)
            XCTFail("Expected missing uninstaller")
        } catch {
            XCTAssertEqual((error as? RuntimeClientError)?.errorDescription, RuntimeControlClientConstants.StatusText.missingUninstaller)
        }
    }

    func testCommandWorkerReportsExecutableInspectionFailureSeparatelyFromMissing() async {
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: AdapterFakeActionEnvironment(executableStates: [
                RuntimeControlClientConstants.Paths.launcher: .inspectFailed("permission denied"),
                RuntimeControlClientConstants.Paths.uninstaller: .present,
            ]),
            logExporter: AdapterFakeLogExporter()
        )

        do {
            _ = try await worker.verifyUpdateBundle(url: URL(fileURLWithPath: "/bundle"))
            XCTFail("Expected launcher inspection failure")
        } catch {
            XCTAssertTrue((error as? RuntimeClientError)?.errorDescription?.contains("launcher inspection failed") == true)
            XCTAssertTrue((error as? RuntimeClientError)?.errorDescription?.contains("permission denied") == true)
        }
        do {
            _ = try await worker.uninstallRuntime(mode: .standard)
            XCTFail("Expected uninstaller not executable")
        } catch {
            XCTAssertTrue((error as? RuntimeClientError)?.errorDescription?.contains("not executable") == true)
            XCTAssertTrue((error as? RuntimeClientError)?.errorDescription?.contains("state=present") == true)
        }
    }

    func testDeleteBackupRejectsTargetsOutsideManagedBackupRootBeforePrivilegedCommand() async {
        let runner = AdapterFakePrivilegedCommandRunner()
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: runner,
            actionEnvironment: AdapterFakeActionEnvironment(),
            logExporter: AdapterFakeLogExporter()
        )

        do {
            _ = try await worker.deleteBackup(url: URL(fileURLWithPath: "/tmp/20260522-before-0.1.3"))
            XCTFail("Expected invalid backup deletion target")
        } catch {
            XCTAssertTrue(
                (error as? RuntimeClientError)?.errorDescription?.contains("outside the managed backup directory") == true
            )
        }
        XCTAssertEqual(runner.shellCommands, [])
    }

    func testCommandWorkerReturnsPrivilegedCommandResultsForBackupDeleteAndProxyRepair() async throws {
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: AdapterFakeActionEnvironment(),
            logExporter: AdapterFakeLogExporter()
        )

        let deleteUpdateBackup = try await worker.deleteBackup(
            url: URL(fileURLWithPath: "\(RuntimeControlClientConstants.Paths.backups)/20260522-before-0.1.3")
        )
        let deleteRuntimeDataBackup = try await worker.deleteBackup(
            url: URL(fileURLWithPath: "\(RuntimeControlClientConstants.Paths.runtimeDataBackups)/20260613T000000Z-manual")
        )
        let repair = try await worker.repairProxy()

        XCTAssertEqual(deleteUpdateBackup.stdout, "ran")
        XCTAssertEqual(deleteRuntimeDataBackup.stdout, "ran")
        XCTAssertEqual(repair.stdout, "ran")
    }
}

final class RuntimeExecutableCommandPreflightTests: XCTestCase {
    func testExecutableStatePassesWithoutError() throws {
        XCTAssertNoThrow(try RuntimeExecutableCommandPreflight.requireExecutable(
            state: .executable,
            requirement: .launcher
        ))
    }

    func testMissingLauncherStaysMissingLauncherError() {
        assertPreflightError(
            state: .missing,
            requirement: .launcher,
            contains: RuntimeControlClientConstants.StatusText.missingLauncher
        )
    }

    func testInspectionFailureStaysDistinctFromMissing() {
        assertPreflightError(
            state: .inspectFailed("permission denied"),
            requirement: .launcher,
            contains: "launcher inspection failed"
        )
        assertPreflightError(
            state: .inspectFailed("permission denied"),
            requirement: .launcher,
            contains: "permission denied"
        )
    }

    func testPresentButNotExecutableStaysDistinctFromMissing() {
        assertPreflightError(
            state: .present,
            requirement: .uninstaller,
            contains: "Uninstaller is not executable"
        )
        assertPreflightError(
            state: .present,
            requirement: .uninstaller,
            contains: "state=present"
        )
    }

    func testUnknownExecutableStateIsReportedAsNotExecutableState() {
        assertPreflightError(
            state: .unknown("acl-denied"),
            requirement: .uninstaller,
            contains: "state=acl-denied"
        )
    }

    private func assertPreflightError(
        state: RuntimeFileState,
        requirement: RuntimeExecutableRequirement,
        contains expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try RuntimeExecutableCommandPreflight.requireExecutable(state: state, requirement: requirement)
            XCTFail("Expected executable preflight failure", file: file, line: line)
        } catch {
            XCTAssertTrue(
                (error as? RuntimeClientError)?.errorDescription?.contains(expected) == true,
                "Expected error to contain \(expected), got \(String(describing: error))",
                file: file,
                line: line
            )
        }
    }
}

private final class AdapterStubStatusReader: RuntimeStatusReading {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        RuntimeStatus(statusMessage: "status")
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        RuntimeStatus(statusMessage: "health")
    }
}

private final class AdapterStubObservabilityReader: RuntimeObservabilityReading {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [], matchingCount: limit)
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [], matchingCount: query.limit)
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.loaded(VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        ))
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory()
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory(readError: "relationships")
    }
}

private final class AdapterStubFileReader: RuntimeHostFileReading {
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult {
        .loaded("summary:\(url.path)")
    }

    func backups(latestBackupPath: String?) throws -> [RuntimeBackup] {
        [RuntimeBackup(path: latestBackupPath ?? "/backup", sizeBytes: 1)]
    }

    func redisBackups() throws -> [RuntimeBackup] {
        [RuntimeBackup(path: "/redis/latest", sizeBytes: 2)]
    }

    func runtimeDataBackups() throws -> [RuntimeBackup] {
        [RuntimeBackup(path: "/runtime-data/latest", sizeBytes: 3)]
    }

    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult {
        .loaded("log:\(sourceID.rawValue):\(lineLimit)")
    }

    func preferredLogsPath() -> String {
        "/logs"
    }

    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] {
        [VitalFilesFolder(name: "vital", path: root)]
    }
}

private final class AdapterStubSettingsReader: RuntimeSettingsReading {
    func load() -> RuntimeSettings {
        var settings = RuntimeSettings()
        settings.proxyPort = 19080
        return settings
    }
}

private final class AdapterFakePrivilegedCommandRunner: PrivilegedCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var protectedShellCommands: [String] = []

    var shellCommands: [String] {
        lock.withLock { protectedShellCommands }
    }

    func run(shellCommand: String) async -> RuntimeCommandResult {
        lock.withLock {
            protectedShellCommands.append(shellCommand)
        }
        return RuntimeCommandResult(exitCode: 0, stdout: "ran", stderr: "")
    }
}

private final class AdapterFakeActionEnvironment: RuntimeActionEnvironment, @unchecked Sendable {
    let executableStates: [String: RuntimeFileState]
    var removeError: Error?
    var removeErrorPaths: Set<String>?
    var redisRelaySettingsWriteError: Error?
    private let lock = NSLock()
    private var protectedRemovedTemporaryFiles: [URL] = []
    private var protectedWrittenRecorderIngressSettings: [RuntimeRecorderIngressSettings] = []
    private var protectedWrittenRedisRelaySettings: [RuntimeRedisRelaySettings] = []

    init(executableStates: [String: RuntimeFileState] = [
        RuntimeControlClientConstants.Paths.launcher: .executable,
        RuntimeControlClientConstants.Paths.uninstaller: .executable,
    ]) {
        self.executableStates = executableStates
    }

    var removedTemporaryFiles: [URL] {
        lock.withLock { protectedRemovedTemporaryFiles }
    }

    var writtenRedisRelaySettings: [RuntimeRedisRelaySettings] {
        lock.withLock { protectedWrittenRedisRelaySettings }
    }

    var writtenRecorderIngressSettings: [RuntimeRecorderIngressSettings] {
        lock.withLock { protectedWrittenRecorderIngressSettings }
    }

    func executableState(atPath path: String) -> RuntimeFileState {
        executableStates[path] ?? .missing
    }

    func writeAdminPasswordFile(_ password: String) throws -> URL {
        URL(fileURLWithPath: "/tmp/admin-password")
    }

    func writeRecorderIngressSettingsFile(_ settings: RuntimeRecorderIngressSettings) throws -> URL {
        lock.withLock {
            protectedWrittenRecorderIngressSettings.append(settings)
        }
        return URL(fileURLWithPath: "/tmp/recorder-ingress-settings.json")
    }

    func writeRedisRelaySettingsFile(_ settings: RuntimeRedisRelaySettings) throws -> URL {
        if let redisRelaySettingsWriteError {
            throw redisRelaySettingsWriteError
        }
        lock.withLock {
            protectedWrittenRedisRelaySettings.append(settings)
        }
        return URL(fileURLWithPath: "/tmp/redis-relay-settings.json")
    }

    func removeItem(at url: URL) throws {
        lock.withLock {
            protectedRemovedTemporaryFiles.append(url)
        }
        if let removeError, removeErrorPaths?.contains(url.path) ?? true {
            throw removeError
        }
    }

    func verifyBundle(launcher: String, bundleURL: URL) async -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "verified:\(bundleURL.path)", stderr: "")
    }
}

private final class AdapterFakeLogExporter: RuntimeLogExporting, @unchecked Sendable {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        RuntimeLogExportResult(destination: destination)
    }
}

private struct AdapterFakeGuestMaintenanceController: RuntimeGuestMaintenanceCommandControlling {
    func createRedisBackup(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "redis-backup-1",
            service: "redis-backup",
            command: .redisBackup,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            result: RuntimeGuestControlOperationResult(
                archive: "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
            )
        )
    }

    func restoreRedisBackup(
        archive: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "redis-restore-1",
            service: "redis-restore",
            command: .redisRestore,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            result: RuntimeGuestControlOperationResult(
                restoredArchive: archive
            )
        )
    }

    func repairDatastore(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "datastore-repair-1",
            service: "datastore-repair",
            command: .repairDatastore,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00"
        )
    }

    func activateUpdate(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "update-activation-1",
            service: "update-activation",
            command: .updateActivation,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            result: RuntimeGuestControlOperationResult(
                requestId: requestId,
                version: version
            )
        )
    }

    func prepareUpdateShutdown(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "update-shutdown-1",
            service: "update-shutdown",
            command: .updateShutdown,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            result: RuntimeGuestControlOperationResult(
                requestId: requestId,
                version: version,
                shutdownPhase: "poweroff-ready"
            )
        )
    }

    func requestGuestPoweroff(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "guest-poweroff-1",
            service: "guest-poweroff",
            command: .requestGuestPoweroff,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00"
        )
    }
}

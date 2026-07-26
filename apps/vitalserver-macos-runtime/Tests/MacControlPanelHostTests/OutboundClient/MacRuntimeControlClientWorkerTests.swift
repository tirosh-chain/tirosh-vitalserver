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
        let platformStateReader = AdapterStubStatusReader()
        let operationStateReader = AdapterStubOperationStateReader(activeOperation: .applyBundle)
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
            platformStateReader: platformStateReader,
            operationStateReader: operationStateReader,
            observabilityReader: observabilityReader,
            fileReader: fileReader,
            settingsReader: settingsReader
        )

        let settings = await worker.loadSettings()
        let status = await worker.loadPlatformState(settings: settings)
        let health = await worker.loadHealthStatus(settings: settings)
        let operationState = await worker.loadOperationState()
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
        XCTAssertEqual(status.installedVersion, "status")
        XCTAssertEqual(health.installedVersion, "health")
        XCTAssertEqual(operationState.activeOperation, .applyBundle)
        XCTAssertEqual(operationState.lease.state, .failed)
        XCTAssertEqual(operationState.lease.readError, "lease read failed")
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
            guestAddressProvider: AdapterStubGuestAddressProvider.loaded,
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
            platformStateReader: AdapterStubStatusReader(),
            observabilityReader: AdapterStubObservabilityReader(),
            fileReader: AdapterStubFileReader(),
            settingsReader: AdapterStubSettingsReader(),
            commandWorker: commandWorker
        )

        let healthStatus = await client.loadHealthStatus(settings: RuntimeSettings())
        let verification = try await client.verifyUpdateBundle(url: URL(fileURLWithPath: "/bundle"))
        let export = try await client.exportLogs(to: URL(fileURLWithPath: "/tmp/logs.zip"))
        let loadedReleaseInfo = try await client.loadReleaseInfo()

        XCTAssertFalse(client.capabilities.canApplyBundle)
        XCTAssertEqual(client.loadSettings().proxyPort, 19080)
        XCTAssertEqual(client.loadPlatformState(settings: RuntimeSettings()).installedVersion, "status")
        XCTAssertEqual(healthStatus.installedVersion, "health")
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
        XCTAssertEqual(
            verification.stdout,
            "integrity-checked publisher-authenticity-unverified:/bundle"
        )
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
        ])
        XCTAssertEqual(runner.shellCommands.count, 8)
        XCTAssertTrue(runner.shellCommands.contains { $0.contains("--clean") })
        XCTAssertFalse(runner.shellCommands.contains { $0.contains("--force-clean-uninstaller") })
        XCTAssertTrue(runner.shellCommands.contains { $0.contains("--admin-password-file") })
        let applyCommand = try XCTUnwrap(
            runner.shellCommands.first { $0.contains("apply-bundle") }
        )
        XCTAssertFalse(applyCommand.contains("--allow-unsigned-dev-bundle"))
    }

    func testCommandWorkerPreservesFailedGuestDatastoreRepairOperation() async throws {
        let failure = RuntimeGuestControlOperationFailure(
            kind: "datastore-repair-failed",
            message: "redis append-only file repair failed"
        )
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: AdapterFakeActionEnvironment(),
            logExporter: AdapterFakeLogExporter(),
            guestMaintenanceController: AdapterFakeGuestMaintenanceController(
                datastoreRepairOperation: RuntimeGuestControlServiceOperation(
                    operationId: "datastore-repair-1",
                    service: "datastore-repair",
                    command: .repairDatastore,
                    state: .failed,
                    createdAt: "2026-07-01T00:00:00+00:00",
                    updatedAt: "2026-07-01T00:00:01+00:00",
                    failure: failure
                )
            ),
            guestAddressProvider: AdapterStubGuestAddressProvider.loaded,
            guestControlBaseURLOverride: "http://127.0.0.1:18330"
        )

        let operation = try await worker.requestDatastoreRepair()

        XCTAssertEqual(operation.state, .failed)
        XCTAssertEqual(operation.failure, failure)
    }

    func testOperationStateReaderPreservesLeaseReadStates() {
        let now = ISO8601DateFormatter().date(from: "2026-07-08T00:00:10Z")!
        let activeLease = RuntimeOperationLeaseDocument(
            operationId: "active-lease",
            operation: .applyBundle,
            ownerPID: 101,
            startedAt: "2026-07-08T00:00:00Z",
            heartbeatAt: "2026-07-08T00:00:05Z",
            expiresAt: "2026-07-08T00:01:00Z",
            message: "active"
        )
        let expiredLease = RuntimeOperationLeaseDocument(
            operationId: "expired-lease",
            operation: .applyBundle,
            ownerPID: 101,
            startedAt: "2026-07-08T00:00:00Z",
            heartbeatAt: "2026-07-08T00:00:05Z",
            expiresAt: "2026-07-08T00:00:00Z",
            message: "expired"
        )

        let missing = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .missing),
            now: { now }
        ).loadOperationState()
        let failed = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .failed("lease denied")),
            now: { now }
        ).loadOperationState()
        let loaded = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .loaded(activeLease)),
            now: { now }
        ).loadOperationState()
        let stale = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .loaded(expiredLease)),
            now: { now }
        ).loadOperationState()

        XCTAssertEqual(missing.lease.state, .unavailable)
        XCTAssertNil(missing.lease.document)

        XCTAssertEqual(failed.lease.state, .failed)
        XCTAssertEqual(failed.lease.readError, "lease denied")

        XCTAssertEqual(loaded.activeOperation, .applyBundle)
        XCTAssertEqual(loaded.operationForPresentation, .applyBundle)
        XCTAssertEqual(loaded.lease.state, .loaded)
        XCTAssertEqual(loaded.lease.document, activeLease)

        XCTAssertNil(stale.activeOperation)
        XCTAssertEqual(stale.lease.state, .stale)
        XCTAssertEqual(stale.lease.document, expiredLease)
        XCTAssertTrue(stale.lease.staleReason?.contains("expired-lease") == true)
    }

    func testOperationStateReaderPreservesInstallReadStates() {
        let installDocument = RuntimeInstallStateDocument(
            state: .stepStarted,
            mode: .full,
            currentStep: .replaceRootfsBase,
            updatedAt: "2026-07-08T00:00:00Z",
            message: "install step running"
        )

        let unavailable = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .missing)
        ).loadOperationState()
        let loaded = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .missing),
            installStateReader: {
                RuntimeInstallStateRead.loaded(installDocument)
            }
        ).loadOperationState()
        let failed = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .missing),
            installStateReader: {
                RuntimeInstallStateRead.failed("runtime install state decode failed")
            }
        ).loadOperationState()

        XCTAssertEqual(unavailable.install.state, .unavailable)
        XCTAssertNil(unavailable.activeOperation)

        XCTAssertEqual(loaded.install.state, .loaded)
        XCTAssertEqual(loaded.install.document, installDocument)
        XCTAssertNil(loaded.activeOperation)

        XCTAssertEqual(failed.install.state, .failed)
        XCTAssertEqual(failed.install.readError, "runtime install state decode failed")
        XCTAssertNil(failed.activeOperation)
    }

    func testOperationStateReaderMapsLatestSQLiteWorkflowStateWithoutInferringActiveOperation() {
        let state = RuntimeWorkflowOperationState(
            operationID: "operation-1",
            operation: .applyBundle,
            phase: .completed,
            currentStep: nil,
            stepStatus: nil,
            message: "bundle applied",
            reasonCodes: [],
            startedAt: "2026-07-14T06:00:00Z",
            updatedAt: "2026-07-14T06:05:00Z",
            completedAt: "2026-07-14T06:05:00Z",
            revision: 9
        )
        let loaded = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .missing),
            workflowOperationStateReader: AdapterStubWorkflowOperationStateReader(result: .loaded(state))
        ).loadOperationState()
        let failed = SystemPlatformOperationStateReader(
            operationLeaseReader: AdapterStubOperationLeaseReader(loadResult: .missing),
            workflowOperationStateReader: AdapterStubWorkflowOperationStateReader(result: .failed("database denied"))
        ).loadOperationState()

        XCTAssertNil(loaded.activeOperation)
        XCTAssertEqual(loaded.workflow.state, .loaded)
        XCTAssertEqual(loaded.workflow.document?.operationID, "operation-1")
        XCTAssertEqual(loaded.workflow.document?.phase, .completed)
        XCTAssertEqual(loaded.workflow.document?.revision, 9)
        XCTAssertEqual(failed.workflow.state, .failed)
        XCTAssertEqual(failed.workflow.readError, "database denied")
    }

    func testApplySettingsReportsAdminPasswordCleanupFailureAsOutputIssue() async throws {
        let environment = AdapterFakeActionEnvironment()
        environment.removeError = CocoaError(.fileWriteNoPermission)
        environment.removeErrorPaths = ["/tmp/admin-password"]
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: environment,
            logExporter: AdapterFakeLogExporter(),
            guestAddressProvider: AdapterStubGuestAddressProvider.loaded
        )
        var settings = RuntimeSettings()
        settings.changeAdminPassword = true
        settings.adminPassword = "secret"

        let result = try await worker.applySettings(settings)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(environment.removedTemporaryFiles.map(\.path), [
            "/tmp/admin-password",
            "/tmp/recorder-ingress-settings.json",
        ])
        XCTAssertEqual(result.outputIssues.count, 1)
        XCTAssertEqual(result.outputIssues.first?.stream, .stderr)
        XCTAssertTrue(result.outputIssues.first?.message.contains("admin password file cleanup failed") == true)
        XCTAssertTrue(result.outputIssues.first?.message.contains("/tmp/admin-password") == true)
    }

    func testCommandWorkerReportsMissingExecutableBoundaries() async {
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: AdapterFakeActionEnvironment(executableStates: [
                RuntimeControlClientConstants.Paths.launcher: .missing,
                RuntimeControlClientConstants.Paths.uninstaller: .missing,
            ]),
            logExporter: AdapterFakeLogExporter(),
            guestAddressProvider: AdapterStubGuestAddressProvider.loaded
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
            logExporter: AdapterFakeLogExporter(),
            guestAddressProvider: AdapterStubGuestAddressProvider.loaded
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
            logExporter: AdapterFakeLogExporter(),
            guestAddressProvider: AdapterStubGuestAddressProvider.loaded
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
            logExporter: AdapterFakeLogExporter(),
            guestAddressProvider: AdapterStubGuestAddressProvider.loaded
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

    func testCommandWorkerUsesGuestAddressProviderForGuestControlBaseURL() async throws {
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: AdapterFakeActionEnvironment(),
            logExporter: AdapterFakeLogExporter(),
            guestAddressProvider: AdapterStubGuestAddressProvider(
                result: .readFailed("vm-ip file read denied")
            )
        )

        let scenarios = try await worker.loadLabScenarios()

        XCTAssertEqual(scenarios.state, .unavailable)
        XCTAssertTrue(scenarios.readError?.contains("guest-address-read-failed:vm-ip file read denied") == true)
        XCTAssertTrue(scenarios.readError?.contains("runtime status document") == false)
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

private final class AdapterStubStatusReader: PlatformStateReading {
    func loadPlatformState(settings: RuntimeSettings) -> PlatformState {
        platformState(runtimeVersion: "status")
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
        platformState(runtimeVersion: "health")
    }
}

private final class AdapterStubOperationStateReader: PlatformOperationStateReading {
    let activeOperation: RuntimeOperation?

    init(activeOperation: RuntimeOperation? = nil) {
        self.activeOperation = activeOperation
    }

    func loadOperationState() -> PlatformOperationState {
        PlatformOperationState(
            activeOperation: activeOperation,
            install: .unavailable(),
            lease: .failed(readError: "lease read failed")
        )
    }
}

private struct AdapterStubOperationLeaseReader: RuntimeOperationLeaseReading {
    let result: RuntimeOperationLeaseLoadResult

    init(loadResult: RuntimeOperationLeaseLoadResult) {
        self.result = loadResult
    }

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        result
    }
}

private struct AdapterStubWorkflowOperationStateReader: RuntimeWorkflowOperationStateReading {
    let result: RuntimeWorkflowOperationStateReadResult

    func loadOperationState(operationID: String) -> RuntimeWorkflowOperationStateReadResult {
        result
    }

    func loadLatestOperationState() -> RuntimeWorkflowOperationStateReadResult {
        result
    }

    func loadLatestOperationState(operation: RuntimeOperation) -> RuntimeWorkflowOperationStateReadResult {
        result
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
    private let lock = NSLock()
    private var protectedRemovedTemporaryFiles: [URL] = []
    private var protectedWrittenRecorderIngressSettings: [RuntimeRecorderIngressSettings] = []

    init(executableStates: [String: RuntimeFileState] = [
        RuntimeControlClientConstants.Paths.launcher: .executable,
        RuntimeControlClientConstants.Paths.uninstaller: .executable,
    ]) {
        self.executableStates = executableStates
    }

    var removedTemporaryFiles: [URL] {
        lock.withLock { protectedRemovedTemporaryFiles }
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

    func removeItem(at url: URL) throws {
        lock.withLock {
            protectedRemovedTemporaryFiles.append(url)
        }
        if let removeError, removeErrorPaths?.contains(url.path) ?? true {
            throw removeError
        }
    }

    func verifyBundle(launcher: String, bundleURL: URL) async -> RuntimeCommandResult {
        RuntimeCommandResult(
            exitCode: 0,
            stdout: "integrity-checked publisher-authenticity-unverified:\(bundleURL.path)",
            stderr: ""
        )
    }
}

private final class AdapterFakeLogExporter: RuntimeLogExporting, @unchecked Sendable {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        RuntimeLogExportResult(destination: destination)
    }
}

private struct AdapterStubGuestAddressProvider: RuntimeGuestAddressProvider {
    let result: RuntimeGuestAddressReadResult

    static let loaded = AdapterStubGuestAddressProvider(
        result: .loaded(address: "192.168.64.2", source: .platformAgent)
    )

    func readGuestAddress() -> RuntimeGuestAddressReadResult {
        result
    }
}

private struct AdapterFakeGuestMaintenanceController: RuntimeGuestMaintenanceCommandControlling {
    private static let completedDatastoreRepairOperation = RuntimeGuestControlServiceOperation(
        operationId: "datastore-repair-1",
        service: "datastore-repair",
        command: .repairDatastore,
        state: .completed,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00"
    )
    let datastoreRepairOperation: RuntimeGuestControlServiceOperation

    init(
        datastoreRepairOperation: RuntimeGuestControlServiceOperation = Self.completedDatastoreRepairOperation
    ) {
        self.datastoreRepairOperation = datastoreRepairOperation
    }

    func createPostgresBackup(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "postgres-backup-1",
            service: "postgres-backup",
            command: .postgresBackup,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            result: RuntimeGuestControlOperationResult(
                archive: "/mnt/tirosh/backups/postgres/postgres-20260701.tar.gz"
            )
        )
    }

    func restorePostgresBackup(
        archive: String,
        restartRuntime: Bool,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: "postgres-restore-1",
            service: "postgres-restore",
            command: .postgresRestore,
            state: .completed,
            createdAt: "2026-07-01T00:00:00+00:00",
            updatedAt: "2026-07-01T00:00:01+00:00",
            result: RuntimeGuestControlOperationResult(restoredArchive: archive)
        )
    }

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

    func requestDatastoreRepair(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        datastoreRepairOperation
    }

    func repairDatastore(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        datastoreRepairOperation
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
                shutdownPhase: "poweroff-ready",
                redisBackupPath: "/mnt/tirosh/backups/redis/update.tar.gz",
                postgresBackupPath: "/mnt/tirosh/backups/postgres/update.tar.gz"
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

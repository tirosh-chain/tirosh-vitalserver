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
        let worker = MacHostRuntimeReadWorker(
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
        let observation = await worker.loadVitalDBObservation()
        let snapshot = await worker.loadVitalDBObservationSnapshot()
        let recorders = await worker.loadVitalDBRecorders()
        let relationships = await worker.loadVitalDBRelationships()
        let backups = try await worker.loadBackups(latestBackupPath: "/backup/latest")
        let redisBackups = try await worker.loadRedisBackups()
        let summary = await worker.updateBundleSummary(url: URL(fileURLWithPath: "/bundle"))
        let folders = try await worker.vitalFileFolders(root: "/vital")
        let releaseInfo = await worker.loadReleaseInfo()
        let installInfo = await worker.loadInstallInfo()

        XCTAssertEqual(settings.proxyPort, 19080)
        XCTAssertEqual(status.statusMessage, "status")
        XCTAssertEqual(health.statusMessage, "health")
        XCTAssertEqual(limitedEvents.matchingCount, 5)
        XCTAssertEqual(queriedEvents.matchingCount, 7)
        XCTAssertEqual(observation?.observedAt, "2026-05-30T00:00:00Z")
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-30T00:00:00Z")
        XCTAssertEqual(recorders.recorders.count, 0)
        XCTAssertEqual(relationships.readError, "relationships")
        XCTAssertEqual(backups.map(\.path), ["/backup/latest"])
        XCTAssertEqual(redisBackups.map(\.path), ["/redis/latest"])
        XCTAssertEqual(summary, "summary:/bundle")
        XCTAssertEqual(folders.map(\.path), ["/vital"])
        XCTAssertEqual(releaseInfo.helperVersion, "helper")
        XCTAssertFalse(installInfo.runtimeHomePath?.isEmpty ?? true)
    }

    func testClientDelegatesReadsAndCommandsToWorkers() async throws {
        let runner = AdapterFakePrivilegedCommandRunner()
        let environment = AdapterFakeActionEnvironment()
        let exporter = AdapterFakeLogExporter()
        let commandWorker = MacHostRuntimeCommandWorker(
            privilegedCommandRunner: runner,
            actionEnvironment: environment,
            logExporter: exporter
        )
        let releaseInfo = RuntimeReleaseInfo(
            helperVersion: "helper",
            minimumUpdaterVersion: "1",
            vitalServerVersion: "runtime",
            services: []
        )
        let client = MacHostRuntimeClient(
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
        XCTAssertNotNil(client.loadVitalDBObservation())
        XCTAssertNotNil(client.loadVitalDBObservationSnapshot().observation)
        XCTAssertEqual(client.loadVitalDBRecorders().recorders.count, 0)
        XCTAssertEqual(client.loadVitalDBRelationships().readError, "relationships")
        let backups = try client.loadBackups(latestBackupPath: "/backup/latest")
        let redisBackups = try client.loadRedisBackups()
        let folders = try client.vitalFileFolders(root: "/vital")
        XCTAssertEqual(backups.map { $0.path }, ["/backup/latest"])
        XCTAssertEqual(redisBackups.map { $0.path }, ["/redis/latest"])
        XCTAssertEqual(client.updateBundleSummary(url: URL(fileURLWithPath: "/bundle")), "summary:/bundle")
        XCTAssertEqual(client.logText(sourceID: RuntimeLogSource.command, helperMessage: "", lineLimit: 10), "log:command:10")
        XCTAssertEqual(client.preferredLogsPath(), "/logs")
        XCTAssertEqual(folders.map { $0.name }, ["vital"])
        XCTAssertEqual(verification.stdout, "verified:/bundle")
        XCTAssertEqual(export.destination.path, "/tmp/logs.zip")
        XCTAssertEqual(loadedReleaseInfo, releaseInfo)
        XCTAssertFalse(client.loadInstallInfo().appBundlePath?.isEmpty ?? true)

        _ = try await client.uninstallRuntime(clean: true)
        var settings = RuntimeSettings()
        settings.changeAdminPassword = true
        settings.adminPassword = "secret"
        _ = try await client.applySettings(settings)
        _ = try await client.applyUpdateBundle(url: URL(fileURLWithPath: "/bundle"))
        _ = try await client.rollbackRuntime(backupURL: URL(fileURLWithPath: "/backup"))
        _ = try await client.deleteBackup(url: URL(fileURLWithPath: "/backup/delete"))
        _ = try await client.repairProxy(proxyPort: 18080)
        _ = try await client.repairDatastore()
        _ = try await client.repairVMDisk()
        _ = try await client.repairRuntimeServices()
        _ = try await client.createRedisBackup()
        _ = try await client.startRuntimeServices()
        _ = try await client.stopRuntimeServices()

        XCTAssertEqual(environment.removedPasswordFiles.map(\.path), ["/tmp/admin-password"])
        XCTAssertEqual(runner.shellCommands.count, 12)
        XCTAssertTrue(runner.shellCommands.contains { $0.contains("--clean") })
        XCTAssertTrue(runner.shellCommands.contains { $0.contains("--admin-password-file") })
    }

    func testCommandWorkerReportsMissingExecutableBoundaries() async {
        let worker = MacHostRuntimeCommandWorker(
            privilegedCommandRunner: AdapterFakePrivilegedCommandRunner(),
            actionEnvironment: AdapterFakeActionEnvironment(executablePaths: []),
            logExporter: AdapterFakeLogExporter()
        )

        do {
            _ = try await worker.verifyUpdateBundle(url: URL(fileURLWithPath: "/bundle"))
            XCTFail("Expected missing launcher")
        } catch {
            XCTAssertEqual((error as? RuntimeClientError)?.errorDescription, RuntimeAdapterConstants.StatusText.missingLauncher)
        }
        do {
            _ = try await worker.uninstallRuntime(clean: false)
            XCTFail("Expected missing uninstaller")
        } catch {
            XCTAssertEqual((error as? RuntimeClientError)?.errorDescription, RuntimeAdapterConstants.StatusText.missingUninstaller)
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

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        loadVitalDBObservationSnapshot().observation
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
    func updateBundleSummary(url: URL) -> String {
        "summary:\(url.path)"
    }

    func backups(latestBackupPath: String?) throws -> [RuntimeBackup] {
        [RuntimeBackup(path: latestBackupPath ?? "/backup", sizeBytes: 1)]
    }

    func redisBackups() throws -> [RuntimeBackup] {
        [RuntimeBackup(path: "/redis/latest", sizeBytes: 2)]
    }

    func logText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) -> String {
        "log:\(sourceID.rawValue):\(lineLimit)"
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
    let executablePaths: Set<String>
    private let lock = NSLock()
    private var protectedRemovedPasswordFiles: [URL] = []

    init(executablePaths: Set<String> = [
        RuntimeAdapterConstants.Paths.launcher,
        RuntimeAdapterConstants.Paths.uninstaller,
    ]) {
        self.executablePaths = executablePaths
    }

    var removedPasswordFiles: [URL] {
        lock.withLock { protectedRemovedPasswordFiles }
    }

    func isExecutable(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }

    func writeAdminPasswordFile(_ password: String) throws -> URL {
        URL(fileURLWithPath: "/tmp/admin-password")
    }

    func removeItem(at url: URL) {
        lock.withLock {
            protectedRemovedPasswordFiles.append(url)
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

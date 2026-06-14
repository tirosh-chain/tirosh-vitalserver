import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeDataBackupCompositionTests: XCTestCase {
    func testCreateBackupMapsGuestRedisArchivePathToHostSharedDataPath() throws {
        let fileStore = RuntimeFileStoreSpy()
        let productRoot = URL(fileURLWithPath: "/product")
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let requestURL = installedPaths.guestRunDirectory
            .appendingPathComponent(Constants.Runtime.redisBackupRequestFile)
        let resultURL = installedPaths.guestRunDirectory
            .appendingPathComponent(Constants.Runtime.redisBackupResultFile)
        let hostRedisArchive = installedPaths.redisBackupsDirectory
            .appendingPathComponent("redis-20260610T094159Z.tar.gz")
        let guestRedisArchive = "/mnt/tirosh/backups/redis/redis-20260610T094159Z.tar.gz"

        try writeRequiredRuntimeDataBackupSources(installedPaths, fileStore: fileStore)
        fileStore.files[hostRedisArchive] = Data("redis-archive".utf8)

        let sleeper = RuntimeDataBackupResultSleeper {
            guard let requestData = fileStore.files[requestURL],
                  let request = try? JSONDecoder().decode(RedisBackupRequestDocument.self, from: requestData) else {
                return
            }
            fileStore.files[resultURL] = try? JSONEncoder().encode(RedisBackupResultDocument(
                requestId: request.requestId,
                status: .completed,
                message: "Redis backup completed.",
                archive: guestRedisArchive
            ))
        }
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            clock: RuntimeDataBackupFixedClock(),
            sleeper: sleeper,
            commandRunner: RuntimeDataBackupCommandRunner(),
            serviceManager: RuntimeDataBackupServiceManager(),
            guestGateway: RuntimeDataBackupGuestGateway(),
            fileStore: fileStore
        )

        let backup = try lifecycle.runtimeDataBackupComposition().createBackup()
        let archivedRedis = backup.appendingPathComponent("artifacts/redis-data.tar.gz")
        let manifest = try JSONDecoder().decode(
            RuntimeDataBackupManifest.self,
            from: try fileStore.readData(backup.appendingPathComponent(RuntimeFileNames.backupManifest))
        )

        XCTAssertEqual(try fileStore.readData(archivedRedis), Data("redis-archive".utf8))
        XCTAssertEqual(manifest.artifacts.first { $0.id == .redisData }?.sourcePath, hostRedisArchive.path)
    }

    func testAutomaticBackupRejectsInvalidRetentionBeforeGuestRedisRequest() throws {
        let fileStore = RuntimeFileStoreSpy()
        let productRoot = URL(fileURLWithPath: "/product")
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let requestURL = installedPaths.guestRunDirectory
            .appendingPathComponent(Constants.Runtime.redisBackupRequestFile)
        fileStore.files[installedPaths.guestRuntimeSettings] = try JSONEncoder().encode(
            GuestRuntimeSettingsDocument(
                vitalServerURL: "https://vitalserver.example",
                remoteConsoleURL: "https://console.example",
                publicHost: "vitalserver.example",
                publicPort: 443,
                automaticBackupEnabled: true,
                backupScheduleTimes: ["03:15"],
                backupRetentionCount: 0
            )
        )
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            clock: RuntimeDataBackupFixedClock(),
            sleeper: RuntimeDataBackupResultSleeper {},
            commandRunner: RuntimeDataBackupCommandRunner(),
            serviceManager: RuntimeDataBackupServiceManager(),
            guestGateway: RuntimeDataBackupGuestGateway(),
            fileStore: fileStore
        )

        XCTAssertThrowsError(try lifecycle.runtimeDataBackupComposition().createAutomaticBackup()) { error in
            XCTAssertTrue(String(describing: error).contains("automatic backup retention is invalid value=0"))
        }
        XCTAssertNil(fileStore.files[requestURL])
    }

    private func writeRequiredRuntimeDataBackupSources(
        _ paths: InstalledRuntimePaths,
        fileStore: RuntimeFileStoreSpy
    ) throws {
        fileStore.files[paths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.runtimeVersion)] = Data("""
        {
          "schemaVersion": 1,
          "runtimeVersion": "0.1.13",
          "updatedAt": "2026-06-10T00:00:00Z"
        }
        """.utf8)
        fileStore.files[paths.vmConfig] = Data("{}".utf8)
        fileStore.files[paths.guestRuntimeConfig] = Data("{}".utf8)
        fileStore.files[paths.guestRuntimeSettings] = Data("{}".utf8)
        fileStore.files[paths.proxyLaunchDaemon] = Data("plist".utf8)
    }
}

private struct RuntimeDataBackupFixedClock: RuntimeClock {
    var now: Date {
        ISO8601DateFormatter().date(from: "2026-06-10T09:42:00Z")!
    }
}

private final class RuntimeDataBackupResultSleeper: RuntimeSleeper {
    private let onSleep: () -> Void

    init(onSleep: @escaping () -> Void) {
        self.onSleep = onSleep
    }

    func sleep(forTimeInterval interval: TimeInterval) {
        onSleep()
    }
}

private struct RuntimeDataBackupCommandRunner: RuntimeCommandRunner {
    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct RuntimeDataBackupServiceManager: RuntimeServiceManager {
    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        .loaded
    }

    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct RuntimeDataBackupGuestGateway: RuntimeGuestGateway {
    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument> {
        .loaded(GuestRuntimeStateDocument(
            capabilities: GuestRuntimeCapabilities(
                prepareUpdateShutdown: true,
                activateUpdate: true,
                redisBackup: true,
                redisRestore: true,
                repairDatastore: true
            ),
            vmIP: "192.168.64.2",
            guestHTTP: nil,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil
        ))
    }

    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> { .missing }
    func removeUpdateActivationResult() throws {}
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {}
    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument> { .missing }
    func removeUpdateShutdownResult() throws {}
    func clearUpdateShutdownPreparation() throws {}
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {}
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> { .missing }
    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> { .missing }
}

import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeDataBackupCompositionTests: XCTestCase {
    func testCreateBackupMapsGuestControlRedisArchivePathToHostSharedDataPath() throws {
        let fileStore = RuntimeFileStoreSpy()
        let productRoot = URL(fileURLWithPath: "/product")
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let legacyRequestURL = installedPaths.guestRunDirectory
            .appendingPathComponent("redis-backup.request")
        let hostRedisArchive = installedPaths.redisBackupsDirectory
            .appendingPathComponent("redis-20260610T094159Z.tar.gz")
        let guestRedisArchive = "/mnt/tirosh/backups/redis/redis-20260610T094159Z.tar.gz"
        let guestControlGateway = RuntimeDataBackupGuestControlGateway(
            backupArchive: guestRedisArchive
        )

        try writeRequiredRuntimeDataBackupSources(installedPaths, fileStore: fileStore)
        fileStore.files[hostRedisArchive] = Data("redis-archive".utf8)

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
            runtimeOperationLeaseOwnerFactory: { RuntimeDataBackupOperationLeaseOwner() },
            guestControlGatewayFactory: { guestControlGateway },
            fileStore: fileStore
        )

        let backup = try lifecycle.runtimeDataBackupComposition().createBackup()
        let archivedRedis = backup.appendingPathComponent("artifacts/redis-data.tar.gz")
        let archivedPostgres = backup.appendingPathComponent(
            "artifacts/postgres-database.tar.gz"
        )
        let manifest = try JSONDecoder().decode(
            RuntimeDataBackupManifest.self,
            from: try fileStore.readData(backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest))
        )

        XCTAssertEqual(try fileStore.readData(archivedRedis), Data("redis-archive".utf8))
        XCTAssertEqual(
            try fileStore.readData(archivedPostgres),
            Data("postgres-archive".utf8)
        )
        XCTAssertEqual(manifest.artifacts.first { $0.id == .redisData }?.sourcePath, hostRedisArchive.path)
        XCTAssertNil(fileStore.files[legacyRequestURL])
        XCTAssertEqual(guestControlGateway.createdBackups, 1)
        XCTAssertEqual(guestControlGateway.createdPostgresBackups, 1)
    }

    func testAutomaticBackupRejectsInvalidRetentionBeforeGuestControlOperation() throws {
        let fileStore = RuntimeFileStoreSpy()
        let productRoot = URL(fileURLWithPath: "/product")
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let legacyRequestURL = installedPaths.guestRunDirectory
            .appendingPathComponent("redis-backup.request")
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
            guestControlGatewayFactory: {
                RuntimeDataBackupGuestControlGateway(
                    backupArchive: "/mnt/tirosh/backups/redis/unused.tar.gz"
                )
            },
            fileStore: fileStore
        )

        XCTAssertThrowsError(try lifecycle.runtimeDataBackupComposition().createAutomaticBackup()) { error in
            XCTAssertTrue(String(describing: error).contains("automatic backup retention is invalid value=0"))
        }
        XCTAssertNil(fileStore.files[legacyRequestURL])
    }

    func testAutomaticBackupCreatesHelperBackupAndPrunesOldestArchives() throws {
        let fileStore = RuntimeFileStoreSpy()
        let productRoot = temporaryProductRoot()
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let legacyRequestURL = installedPaths.guestRunDirectory
            .appendingPathComponent("redis-backup.request")
        let hostRedisArchive = installedPaths.redisBackupsDirectory
            .appendingPathComponent("redis-20260610T094159Z.tar.gz")
        let guestRedisArchive = "/mnt/tirosh/backups/redis/redis-20260610T094159Z.tar.gz"
        let guestControlGateway = RuntimeDataBackupGuestControlGateway(
            backupArchive: guestRedisArchive
        )
        let backupRoot = installedPaths.vitalServerHelperBackupsDirectory
        let oldest = backupRoot.appendingPathComponent("20260608T031500Z-automatic")
        let middle = backupRoot.appendingPathComponent("20260609T031500Z-automatic")
        let newestExisting = backupRoot.appendingPathComponent("20260610T031500Z-automatic")

        try writeRequiredRuntimeDataBackupSources(installedPaths, fileStore: fileStore)
        try writeGuestRuntimeSettings(
            installedPaths,
            fileStore: fileStore,
            automaticBackupEnabled: true,
            retentionCount: 2
        )
        fileStore.files[hostRedisArchive] = Data("redis-archive".utf8)
        fileStore.directories.formUnion([backupRoot, oldest, middle, newestExisting])

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
            runtimeOperationLeaseOwnerFactory: { RuntimeDataBackupOperationLeaseOwner() },
            guestControlGatewayFactory: { guestControlGateway },
            fileStore: fileStore
        )

        let message = try lifecycle.runtimeDataBackupComposition().createAutomaticBackup()
        let created = backupRoot.appendingPathComponent("20260610T094200Z-automatic")

        XCTAssertEqual(message, "automatic backup completed: \(created.path)")
        XCTAssertTrue(fileStore.directories.contains(created))
        XCTAssertEqual(fileStore.removed, [oldest, middle])
        XCTAssertFalse(fileStore.directories.contains(oldest))
        XCTAssertFalse(fileStore.directories.contains(middle))
        XCTAssertTrue(fileStore.directories.contains(newestExisting))
        XCTAssertNil(fileStore.files[legacyRequestURL])
        XCTAssertEqual(guestControlGateway.createdBackups, 1)
    }

    func testAutomaticBackupSkipsWhenDisabledWithoutGuestControlOperation() throws {
        let fileStore = RuntimeFileStoreSpy()
        let productRoot = URL(fileURLWithPath: "/product")
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let legacyRequestURL = installedPaths.guestRunDirectory
            .appendingPathComponent("redis-backup.request")
        try writeGuestRuntimeSettings(
            installedPaths,
            fileStore: fileStore,
            automaticBackupEnabled: false,
            retentionCount: 2
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
            guestControlGatewayFactory: {
                RuntimeDataBackupGuestControlGateway(
                    backupArchive: "/mnt/tirosh/backups/redis/unused.tar.gz"
                )
            },
            fileStore: fileStore
        )

        let message = try lifecycle.runtimeDataBackupComposition().createAutomaticBackup()

        XCTAssertEqual(message, "automatic backup skipped: disabled")
        XCTAssertNil(fileStore.files[legacyRequestURL])
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
        fileStore.files[
            paths.postgresBackupsDirectory
                .appendingPathComponent("postgres-20260610T094159Z.tar.gz")
        ] = Data("postgres-archive".utf8)
    }

    private func writeGuestRuntimeSettings(
        _ paths: InstalledRuntimePaths,
        fileStore: RuntimeFileStoreSpy,
        automaticBackupEnabled: Bool,
        retentionCount: Int
    ) throws {
        fileStore.files[paths.guestRuntimeSettings] = try JSONEncoder().encode(
            GuestRuntimeSettingsDocument(
                vitalServerURL: "https://vitalserver.example",
                remoteConsoleURL: "https://console.example",
                publicHost: "vitalserver.example",
                publicPort: 443,
                automaticBackupEnabled: automaticBackupEnabled,
                backupScheduleTimes: ["03:15"],
                backupRetentionCount: retentionCount
            )
        )
    }

    private func temporaryProductRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RuntimeDataBackupCompositionTests-\(UUID().uuidString)")
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

private final class RuntimeDataBackupOperationLeaseOwner: RuntimeOperationLeaseOwner, @unchecked Sendable {
    private var document: RuntimeOperationLeaseDocument?

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        if let document {
            return .loaded(document)
        }
        return .missing
    }

    func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        self.document = document
    }

    func heartbeat(operationId: String, heartbeatAt: String, expiresAt: String?) throws {
        guard let document, document.operationId == operationId else {
            throw RuntimeOperationLeaseOwnerError.readFailed(
                "operation lease missing operationId=\(operationId)"
            )
        }
        self.document = RuntimeOperationLeaseDocument(
            operationId: document.operationId,
            operation: document.operation,
            ownerPID: document.ownerPID,
            startedAt: document.startedAt,
            heartbeatAt: heartbeatAt,
            expiresAt: expiresAt,
            message: document.message
        )
    }

    func release(operationId: String) throws {
        guard document?.operationId == operationId else {
            throw RuntimeOperationLeaseOwnerError.readFailed(
                "operation lease missing operationId=\(operationId)"
            )
        }
        document = nil
    }
}

private final class RuntimeDataBackupGuestControlGateway: RuntimeGuestControlGateway {
    private let backupArchive: String
    private(set) var createdBackups = 0
    private(set) var createdPostgresBackups = 0
    private(set) var restoredArchives: [String] = []

    init(backupArchive: String) {
        self.backupArchive = backupArchive
    }

    func listServices() throws -> RuntimeGuestControlServiceList {
        RuntimeGuestControlServiceList(services: [])
    }

    func stackStatus() throws -> RuntimeGuestControlStackStatus {
        RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-06-10T09:42:00Z",
            services: []
        )
    }

    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        RuntimeGuestControlServiceStatus(
            service: service,
            state: "running",
            health: "healthy",
            observedAt: "2026-06-10T09:42:00Z"
        )
    }

    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        serviceOperation(service: service, command: .start)
    }

    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        serviceOperation(service: service, command: .stop)
    }

    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        serviceOperation(service: service, command: .restart)
    }

    func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        serviceOperation(service: "guest-stack", command: .reconcile)
    }

    func createRedisBackup() throws -> RuntimeGuestControlServiceOperation {
        createdBackups += 1
        return serviceOperation(
            service: "redis-backup",
            command: .redisBackup,
            result: RuntimeGuestControlOperationResult(archive: backupArchive)
        )
    }

    func createPostgresBackup() throws -> RuntimeGuestControlServiceOperation {
        createdPostgresBackups += 1
        return serviceOperation(
            service: "postgres-backup",
            command: .postgresBackup,
            result: RuntimeGuestControlOperationResult(
                archive: "/mnt/tirosh/backups/postgres/postgres-20260610T094159Z.tar.gz",
                databaseId: "cluster:vitalserver",
                alembicRevisions: ["0002_recorder_observability_expectations"]
            )
        )
    }

    func restorePostgresBackup(
        archive: String,
        restartRuntime: Bool
    ) throws -> RuntimeGuestControlServiceOperation {
        restoredArchives.append(archive)
        return serviceOperation(
            service: "postgres-restore",
            command: .postgresRestore,
            result: RuntimeGuestControlOperationResult(
                restoredArchive: archive,
                runtimeRestarted: restartRuntime
            )
        )
    }

    func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation {
        restoredArchives.append(archive)
        return serviceOperation(
            service: "redis-restore",
            command: .redisRestore,
            result: RuntimeGuestControlOperationResult(restoredArchive: archive)
        )
    }

    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        serviceOperation(operationId: operationId)
    }

    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        RuntimeGuestControlVitalDBObservationRead(state: .unavailable)
    }

    private func serviceOperation(
        operationId: String = "guest-control-operation-1",
        service: String = "app",
        command: RuntimeGuestControlServiceCommand = .restart,
        result: RuntimeGuestControlOperationResult? = nil
    ) -> RuntimeGuestControlServiceOperation {
        RuntimeGuestControlServiceOperation(
            operationId: operationId,
            service: service,
            command: command,
            state: .completed,
            createdAt: "2026-06-10T09:42:00Z",
            updatedAt: "2026-06-10T09:42:01Z",
            result: result
        )
    }
}

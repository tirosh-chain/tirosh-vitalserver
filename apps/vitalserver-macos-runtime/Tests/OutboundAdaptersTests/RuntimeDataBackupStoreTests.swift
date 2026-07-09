import Contracts
import OutboundAdapters
import XCTest

final class RuntimeDataBackupStoreTests: XCTestCase {
    private var temporaryRoot: URL!
    private let fileStore = SystemRuntimeFileStore()

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-data-backup-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testCreateBackupArchivesAllRequiredArtifactsAndWritesManifest() throws {
        let paths = try makePaths()
        let redisArchive = temporaryRoot.appendingPathComponent("redis.tar.gz")
        try Data("redis".utf8).write(to: redisArchive)
        try writeRequiredSources(paths)

        let store = RuntimeDataBackupStore(
            paths: paths,
            metadata: RuntimeDataBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                manifestName: RuntimePackageArtifactFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data"
            ),
            timestamp: { "20260610T000000Z" },
            isoTimestamp: { "2026-06-10T00:00:00Z" },
            fileStore: fileStore,
            snapshotSQLiteDatabase: { source, destination in
                try self.fileStore.copyItem(at: source, to: destination)
            }
        )

        let backup = try store.createBackup(
            reason: "manual backup",
            redisArchive: redisArchive,
            startOnBootState: startOnBootStateData()
        )

        XCTAssertEqual(
            backup.path,
            paths.backupsDirectory
                .appendingPathComponent("vitalserver-helper")
                .appendingPathComponent("20260610T000000Z-manual-backup")
                .path
        )
        let manifestURL = backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest)
        let manifest = try JSONDecoder().decode(
            RuntimeDataBackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        XCTAssertEqual(manifest.product, "ai.tirosh.vitalserver.helper")
        XCTAssertEqual(manifest.createdAt, "2026-06-10T00:00:00Z")
        XCTAssertEqual(manifest.runtimeVersion, "0.1.13")
        XCTAssertEqual(
            manifest.restoreCompatibilityVersion,
            RuntimeDataBackupCompatibility.currentRestoreCompatibilityVersion
        )
        XCTAssertEqual(manifest.artifacts.map(\.id), RuntimeDataBackupArtifactID.manifestArtifactOrder)
        XCTAssertEqual(manifest.artifacts.count { $0.id == .runtimeStatusDocument }, 1)
        XCTAssertEqual(manifest.artifacts.count { $0.id == .runtimeEventsDocument }, 1)
        XCTAssertEqual(manifest.artifacts.count { $0.id == .runtimeObservabilityDatabase }, 1)
        XCTAssertTrue(manifest.artifacts.filter { $0.role == .required }.allSatisfy {
            $0.state == .archived && $0.sizeBytes != nil && $0.sha256?.isEmpty == false
        })
        XCTAssertEqual(manifest.artifacts.first?.volumeName, "vitalserver_redis-data")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backup.appendingPathComponent("artifacts/redis-data.tar.gz").path
        ))
        let optionalArtifacts = manifest.artifacts.filter { $0.role == .optional }
        XCTAssertEqual(optionalArtifacts.count, 3)
        for artifact in optionalArtifacts {
            XCTAssertEqual(artifact.state, .archived)
            XCTAssertNotNil(artifact.sizeBytes)
            XCTAssertFalse(artifact.sha256?.isEmpty ?? true)
        }
    }

    func testCreateBackupFailsWhenRequiredArtifactIsMissing() throws {
        let paths = try makePaths()
        let redisArchive = temporaryRoot.appendingPathComponent("missing-redis.tar.gz")
        try writeRequiredSources(paths)

        let store = RuntimeDataBackupStore(
            paths: paths,
            metadata: RuntimeDataBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                manifestName: RuntimePackageArtifactFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data"
            ),
            timestamp: { "20260610T000000Z" },
            isoTimestamp: { "2026-06-10T00:00:00Z" },
            fileStore: fileStore,
            snapshotSQLiteDatabase: { source, destination in
                try self.fileStore.copyItem(at: source, to: destination)
            }
        )

        XCTAssertThrowsError(try store.createBackup(
            reason: "manual",
            redisArchive: redisArchive,
            startOnBootState: Data()
        )) { error in
            XCTAssertEqual(
                error as? RuntimeDataBackupStoreError,
                .requiredArtifactMissing(id: .redisData, path: redisArchive.path)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: paths.backupsDirectory.appendingPathComponent("vitalserver-helper/.staging-20260610T000000Z").path
        ))
    }

    func testCreateBackupSucceedsWhenOptionalArtifactsAreMissing() throws {
        let paths = try makePaths()
        let redisArchive = temporaryRoot.appendingPathComponent("redis.tar.gz")
        try Data("redis".utf8).write(to: redisArchive)
        try writeRequiredSources(paths)
        try FileManager.default.removeItem(at: paths.runtimeStatus)
        try FileManager.default.removeItem(at: paths.runtimeEvents)
        try FileManager.default.removeItem(at: paths.runtimeObservabilityDatabase)

        let store = RuntimeDataBackupStore(
            paths: paths,
            metadata: RuntimeDataBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                manifestName: RuntimePackageArtifactFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data"
            ),
            timestamp: { "20260610T000000Z" },
            isoTimestamp: { "2026-06-10T00:00:00Z" },
            fileStore: fileStore,
            snapshotSQLiteDatabase: { source, destination in
                try self.fileStore.copyItem(at: source, to: destination)
            }
        )

        let backup = try store.createBackup(
            reason: "manual",
            redisArchive: redisArchive,
            startOnBootState: startOnBootStateData()
        )

        let manifest = try JSONDecoder().decode(
            RuntimeDataBackupManifest.self,
            from: Data(contentsOf: backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest))
        )

        let runtimeStatusArtifact = manifest.artifacts.first { $0.id == .runtimeStatusDocument }!
        let runtimeEventsArtifact = manifest.artifacts.first { $0.id == .runtimeEventsDocument }!
        let runtimeObservabilityArtifact = manifest.artifacts.first { $0.id == .runtimeObservabilityDatabase }!

        XCTAssertEqual(runtimeStatusArtifact.role, .optional)
        XCTAssertEqual(runtimeEventsArtifact.role, .optional)
        XCTAssertEqual(runtimeObservabilityArtifact.role, .optional)
        XCTAssertEqual(runtimeStatusArtifact.state, .missing)
        XCTAssertEqual(runtimeEventsArtifact.state, .missing)
        XCTAssertEqual(runtimeObservabilityArtifact.state, .missing)
    }

    func testRestoreBackupSkipsMissingOptionalArtifacts() throws {
        let paths = try makePaths()
        let redisArchive = temporaryRoot.appendingPathComponent("redis.tar.gz")
        try Data("redis".utf8).write(to: redisArchive)
        try writeRequiredSources(paths)
        try FileManager.default.removeItem(at: paths.runtimeStatus)
        try FileManager.default.removeItem(at: paths.runtimeEvents)
        try FileManager.default.removeItem(at: paths.runtimeObservabilityDatabase)

        let store = RuntimeDataBackupStore(
            paths: paths,
            metadata: RuntimeDataBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                manifestName: RuntimePackageArtifactFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data"
            ),
            timestamp: { "20260610T000000Z" },
            isoTimestamp: { "2026-06-10T00:00:00Z" },
            fileStore: fileStore,
            snapshotSQLiteDatabase: { source, destination in
                try self.fileStore.copyItem(at: source, to: destination)
            }
        )
        let backup = try store.createBackup(
            reason: "manual",
            redisArchive: redisArchive,
            startOnBootState: startOnBootStateData()
        )

        try Data("changed-vm".utf8).write(to: paths.vmConfig)
        try Data("changed-runtime-status".utf8).write(to: paths.runtimeStatus)
        try Data("changed-events".utf8).write(to: paths.runtimeEvents)
        try Data("changed-sqlite".utf8).write(to: paths.runtimeObservabilityDatabase)

        _ = try store.restoreBackup(backup)

        XCTAssertEqual(try String(contentsOf: paths.vmConfig), "{}")
        XCTAssertEqual(try String(contentsOf: paths.runtimeStatus), "changed-runtime-status")
        XCTAssertEqual(try String(contentsOf: paths.runtimeEvents), "changed-events")
        XCTAssertEqual(try String(contentsOf: paths.runtimeObservabilityDatabase), "changed-sqlite")
    }

    func testRestoreBackupRestoresRequiredHostArtifactsAndKeepsStatusDiagnosticsCurrent() throws {
        let paths = try makePaths()
        let redisArchive = temporaryRoot.appendingPathComponent("redis.tar.gz")
        try Data("redis".utf8).write(to: redisArchive)
        try writeRequiredSources(paths)
        let store = RuntimeDataBackupStore(
            paths: paths,
            metadata: RuntimeDataBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                manifestName: RuntimePackageArtifactFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data"
            ),
            timestamp: { "20260610T000000Z" },
            isoTimestamp: { "2026-06-10T00:00:00Z" },
            fileStore: fileStore,
            snapshotSQLiteDatabase: { source, destination in
                try self.fileStore.copyItem(at: source, to: destination)
            }
        )
        let backup = try store.createBackup(
            reason: "manual",
            redisArchive: redisArchive,
            startOnBootState: startOnBootStateData()
        )

        try Data("changed-vm".utf8).write(to: paths.vmConfig)
        try Data("changed-guest-config".utf8).write(to: paths.guestRuntimeConfig)
        try Data("changed-settings".utf8).write(to: paths.guestRuntimeSettings)
        try Data("changed-plist".utf8).write(to: paths.proxyLaunchDaemon)
        try Data("changed-status".utf8).write(to: paths.runtimeStatus)
        try Data("changed-events".utf8).write(to: paths.runtimeEvents)
        try Data("changed-sqlite".utf8).write(to: paths.runtimeObservabilityDatabase)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: paths.runtimeObservabilityDatabase.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: paths.runtimeObservabilityDatabase.path + "-shm"))

        let result = try store.restoreBackup(backup)

        XCTAssertEqual(try String(contentsOf: paths.vmConfig), "{}")
        XCTAssertEqual(try String(contentsOf: paths.guestRuntimeConfig), "{}")
        XCTAssertEqual(try String(contentsOf: paths.guestRuntimeSettings), "{}")
        XCTAssertEqual(try String(contentsOf: paths.proxyLaunchDaemon), "plist")
        XCTAssertEqual(try String(contentsOf: paths.runtimeStatus), "changed-status")
        XCTAssertEqual(try String(contentsOf: paths.runtimeEvents), "{}\n")
        XCTAssertEqual(try String(contentsOf: paths.runtimeObservabilityDatabase), "sqlite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.runtimeObservabilityDatabase.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.runtimeObservabilityDatabase.path + "-shm"))
        XCTAssertEqual(result.redisArchive.lastPathComponent, "redis-data.tar.gz")
        XCTAssertEqual(result.startOnBootState.services, [
            RuntimeDataBackupStartOnBootServiceState(label: "ai.tirosh.service", disabled: true)
        ])
    }

    func testRestoreBackupFailsWhenArchivedOptionalDiagnosticsArtifactIsMissing() throws {
        let paths = try makePaths()
        let store = makeStore(paths: paths)
        let backup = try makeBackup(paths: paths, store: store)
        let manifest = try JSONDecoder().decode(
            RuntimeDataBackupManifest.self,
            from: Data(contentsOf: backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest))
        )
        let runtimeEventsArtifact = try XCTUnwrap(
            manifest.artifacts.first { $0.id == .runtimeEventsDocument }
        )
        let backupPath = try XCTUnwrap(runtimeEventsArtifact.backupPath)
        let artifactURL = backup.appendingPathComponent(backupPath)
        try FileManager.default.removeItem(at: artifactURL)

        XCTAssertThrowsError(try store.restoreBackup(backup)) { error in
            XCTAssertEqual(
                error as? RuntimeDataBackupStoreError,
                .optionalArtifactInvalid(
                    id: .runtimeEventsDocument,
                    path: artifactURL.path,
                    reason: "artifact source is missing"
                )
            )
        }
    }

    func testRestoreBackupRejectsMissingRestoreCompatibilityVersion() throws {
        let paths = try makePaths()
        let store = makeStore(paths: paths)
        let backup = try makeBackup(paths: paths, store: store)
        try rewriteManifest(backup: backup) { manifest in
            RuntimeDataBackupManifest(
                schemaVersion: manifest.schemaVersion,
                restoreCompatibilityVersion: nil,
                backupKind: manifest.backupKind,
                product: manifest.product,
                createdAt: manifest.createdAt,
                reason: manifest.reason,
                runtimeVersion: manifest.runtimeVersion,
                sourceRuntimeHome: manifest.sourceRuntimeHome,
                artifacts: manifest.artifacts
            )
        }

        XCTAssertThrowsError(try store.restoreBackup(backup)) { error in
            XCTAssertEqual(
                error as? RuntimeDataBackupStoreError,
                .manifestInvalid(
                    path: backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest).path,
                    errors: ["restoreCompatibilityVersion is missing"]
                )
            )
        }
    }

    func testRestoreBackupRejectsUnsupportedRestoreCompatibilityVersion() throws {
        let paths = try makePaths()
        let store = makeStore(paths: paths)
        let backup = try makeBackup(paths: paths, store: store)
        try rewriteManifest(backup: backup) { manifest in
            RuntimeDataBackupManifest(
                schemaVersion: manifest.schemaVersion,
                restoreCompatibilityVersion: 999,
                backupKind: manifest.backupKind,
                product: manifest.product,
                createdAt: manifest.createdAt,
                reason: manifest.reason,
                runtimeVersion: manifest.runtimeVersion,
                sourceRuntimeHome: manifest.sourceRuntimeHome,
                artifacts: manifest.artifacts
            )
        }

        XCTAssertThrowsError(try store.restoreBackup(backup)) { error in
            XCTAssertEqual(
                error as? RuntimeDataBackupStoreError,
                .manifestInvalid(
                    path: backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest).path,
                    errors: ["restoreCompatibilityVersion must be 1"]
                )
            )
        }
    }

    func testSQLiteSnapshotterCreatesReadableSnapshotFile() throws {
        let source = temporaryRoot.appendingPathComponent("source.sqlite")
        let destination = temporaryRoot.appendingPathComponent("snapshot.sqlite")
        try SQLiteRuntimeObservabilityStore(url: source).initialize()

        try SQLiteRuntimeObservabilitySnapshotter().snapshot(source: source, destination: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertGreaterThan(try fileStore.fileSize(destination), 0)
    }

    private func makePaths() throws -> RuntimeDataBackupStorePaths {
        let runtimeHome = temporaryRoot.appendingPathComponent("runtime-home")
        let backups = runtimeHome.appendingPathComponent("backups")
        let runtime = runtimeHome.appendingPathComponent("runtime")
        let data = runtimeHome.appendingPathComponent("data")
        let status = runtimeHome.appendingPathComponent("status")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: status, withIntermediateDirectories: true)
        return RuntimeDataBackupStorePaths(
            backupsDirectory: backups,
            runtimeHome: runtimeHome,
            runtimeVersion: runtime.appendingPathComponent("runtime-version.json"),
            vmConfig: runtime.appendingPathComponent("vm-config.json"),
            guestRuntimeConfig: data.appendingPathComponent("deploy/runtime-config.json"),
            guestRuntimeSettings: data.appendingPathComponent("deploy/runtime-settings.json"),
            proxyLaunchDaemon: temporaryRoot.appendingPathComponent("proxy.plist"),
            runtimeStatus: status.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeStatus),
            runtimeEvents: status.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeEvents),
            runtimeObservabilityDatabase: status.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)
        )
    }

    private func makeStore(paths: RuntimeDataBackupStorePaths) -> RuntimeDataBackupStore {
        RuntimeDataBackupStore(
            paths: paths,
            metadata: RuntimeDataBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                manifestName: RuntimePackageArtifactFileNames.backupManifest,
                redisVolumeName: "vitalserver_redis-data"
            ),
            timestamp: { "20260610T000000Z" },
            isoTimestamp: { "2026-06-10T00:00:00Z" },
            fileStore: fileStore,
            snapshotSQLiteDatabase: { source, destination in
                try self.fileStore.copyItem(at: source, to: destination)
            }
        )
    }

    private func makeBackup(
        paths: RuntimeDataBackupStorePaths,
        store: RuntimeDataBackupStore
    ) throws -> URL {
        let redisArchive = temporaryRoot.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tar.gz")
        try Data("redis".utf8).write(to: redisArchive)
        try writeRequiredSources(paths)
        return try store.createBackup(
            reason: "manual",
            redisArchive: redisArchive,
            startOnBootState: startOnBootStateData()
        )
    }

    private func rewriteManifest(
        backup: URL,
        transform: (RuntimeDataBackupManifest) -> RuntimeDataBackupManifest
    ) throws {
        let manifestURL = backup.appendingPathComponent(RuntimePackageArtifactFileNames.backupManifest)
        let manifest = try JSONDecoder().decode(
            RuntimeDataBackupManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(transform(manifest)).write(to: manifestURL)
    }

    private func writeRequiredSources(_ paths: RuntimeDataBackupStorePaths) throws {
        try FileManager.default.createDirectory(
            at: paths.guestRuntimeConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        {
          "product": "ai.tirosh.vitalserver.helper",
          "runtimeVersion": "0.1.13",
          "appliedAt": "2026-06-10T00:00:00Z",
          "bundle": "bundle",
          "rootfsBase": "rootfs-base.raw.gz",
          "vmDisk": "vm-disk.img"
        }
        """.utf8).write(to: paths.runtimeVersion)
        try Data("{}".utf8).write(to: paths.vmConfig)
        try Data("{}".utf8).write(to: paths.guestRuntimeConfig)
        try Data("{}".utf8).write(to: paths.guestRuntimeSettings)
        try Data("plist".utf8).write(to: paths.proxyLaunchDaemon)
        try Data("{}".utf8).write(to: paths.runtimeStatus)
        try Data("{}\n".utf8).write(to: paths.runtimeEvents)
        try Data("sqlite".utf8).write(to: paths.runtimeObservabilityDatabase)
    }

    private func startOnBootStateData() throws -> Data {
        try JSONEncoder().encode(RuntimeDataBackupStartOnBootStateDocument(
            schemaVersion: 1,
            capturedAt: "2026-06-10T00:00:00Z",
            services: [
                RuntimeDataBackupStartOnBootServiceState(label: "ai.tirosh.service", disabled: true)
            ]
        ))
    }
}

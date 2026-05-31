import Contracts
import Core
import RuntimeControl
@testable import MacHostRuntimeAdapter
import XCTest
@testable import MacRuntimeControlApp

@MainActor
final class RuntimeSettingsReaderTests: XCTestCase {
    func testLoadsInstalledSettingsFromRuntimeFiles() throws {
        let directory = try temporaryDirectory()
        let vmConfig = directory.appendingPathComponent("vm-config.json")
        let vmDisk = directory.appendingPathComponent("vm-disk.img")
        let guestConfig = directory.appendingPathComponent("runtime-config.json")
        let proxyLaunchDaemon = directory.appendingPathComponent("proxy.plist")

        try """
        {
          "cpuCount": 4,
          "memoryMiB": 6144,
          "network": { "mode": "shared", "bridgedInterface": "en0" },
          "vitalFilesDirectory": { "hostPath": "/Volumes/Vital Files" },
          "autoRecoveryEnabled": false,
          "preventSystemSleep": false
        }
        """.write(to: vmConfig, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: vmDisk.path, contents: Data([0]))
        try """
        {
          "publicHost": "example.test",
          "publicPort": 8080,
          "redisBackupRetentionCount": 31
        }
        """.write(to: guestConfig, atomically: true, encoding: .utf8)
        try writeProxyLaunchDaemon(proxyLaunchDaemon, proxyPort: 19090)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: vmConfig.path,
                vmDisk: vmDisk.path,
                guestRuntimeSettings: directory.appendingPathComponent("missing-runtime-settings.json").path,
                guestRuntimeConfig: guestConfig.path,
                proxyLaunchDaemon: proxyLaunchDaemon.path
            )
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues, [])
        XCTAssertEqual(settings.cpuCount, 4)
        XCTAssertEqual(settings.memoryGiB, 6)
        XCTAssertEqual(settings.diskGiB, 1)
        XCTAssertEqual(settings.minimumDiskGiB, 1)
        XCTAssertEqual(settings.bridgedInterface, "en0")
        XCTAssertEqual(settings.vitalFilesDirectory, "/Volumes/Vital Files")
        XCTAssertEqual(settings.publicHost, "example.test")
        XCTAssertEqual(settings.publicPort, 8080)
        XCTAssertEqual(settings.redisBackupRetentionCount, 30)
        XCTAssertEqual(settings.proxyPort, 19090)
        XCTAssertFalse(settings.autoRecoveryEnabled)
        XCTAssertFalse(settings.preventSystemSleep)
    }

    func testReportsSettingsReadIssuesWithoutReplacingMissingFilesWithErrors() throws {
        let directory = try temporaryDirectory()
        let vmConfig = directory.appendingPathComponent("vm-config.json")
        let proxyLaunchDaemon = directory.appendingPathComponent("proxy.plist")
        try Data("not-json".utf8).write(to: vmConfig)
        try writeProxyLaunchDaemon(proxyLaunchDaemon, proxyPort: 70_000)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: vmConfig.path,
                vmDisk: directory.appendingPathComponent("missing-disk.img").path,
                guestRuntimeConfig: directory.appendingPathComponent("missing-runtime-config.json").path,
                proxyLaunchDaemon: proxyLaunchDaemon.path
            )
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues.map(\.source), ["vmConfig", "proxyLaunchDaemon"])
        XCTAssertEqual(settings.cpuCount, RuntimeSettings().cpuCount)
        XCTAssertEqual(settings.proxyPort, RuntimeSettings().proxyPort)
    }

    func testDoesNotReportGuestRuntimeConfigPermissionIssueForSecretFile() throws {
        let guestConfig = URL(fileURLWithPath: "/product/vm/data/deploy/runtime-config.json")
        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: "/missing/vm-config.json",
                vmDisk: "/missing/vm-disk.img",
                guestRuntimeConfig: guestConfig.path,
                proxyLaunchDaemon: "/missing/proxy.plist"
            ),
            fileStore: GuestRuntimeConfigPermissionDeniedFileStore(guestConfig: guestConfig)
        )

        let settings = reader.load()

        XCTAssertFalse(settings.readIssues.contains { $0.source == "guestRuntimeConfig" })
        XCTAssertEqual(settings.publicHost, RuntimeSettings().publicHost)
        XCTAssertEqual(settings.publicPort, RuntimeSettings().publicPort)
    }

    func testReportsSettingsReadFailuresForNonSecretRuntimeFiles() {
        let paths = RuntimeSettingsPaths(
            vmConfig: "/missing/vm-config.json",
            vmDisk: "/runtime/vm-disk.img",
            guestRuntimeSettings: "/runtime/runtime-settings.json",
            guestRuntimeConfig: "/runtime/runtime-config.json",
            proxyLaunchDaemon: "/runtime/proxy.plist"
        )
        let reader = SystemRuntimeSettingsReader(
            paths: paths,
            fileStore: SettingsReadFailureFileStore(existingPaths: [
                paths.vmDisk,
                paths.guestRuntimeSettings,
                paths.guestRuntimeConfig,
                paths.proxyLaunchDaemon,
            ])
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues.map(\.source), [
            "vmDisk",
            "guestRuntimeSettings",
            "guestRuntimeConfig",
            "proxyLaunchDaemon",
        ])
        XCTAssertTrue(settings.readIssues[0].message.contains("disk size denied"))
        XCTAssertTrue(settings.readIssues[1].message.contains("runtime settings denied"))
        XCTAssertTrue(settings.readIssues[2].message.contains("invalid legacy runtime config"))
        XCTAssertTrue(settings.readIssues[3].message.contains("proxy plist denied"))
    }

    func testLoadsGuestRuntimeSettingsBeforeSecretRuntimeConfig() throws {
        let directory = try temporaryDirectory()
        let guestSettings = directory.appendingPathComponent("runtime-settings.json")
        let guestConfig = directory.appendingPathComponent("runtime-config.json")
        try """
        {
          "publicHost": "settings.example.test",
          "publicPort": 8443,
          "redisBackupRetentionCount": 12
        }
        """.write(to: guestSettings, atomically: true, encoding: .utf8)
        try """
        {
          "publicHost": "secret.example.test",
          "publicPort": 8080,
          "redisBackupRetentionCount": 20
        }
        """.write(to: guestConfig, atomically: true, encoding: .utf8)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: directory.appendingPathComponent("missing-vm-config.json").path,
                vmDisk: directory.appendingPathComponent("missing-disk.img").path,
                guestRuntimeSettings: guestSettings.path,
                guestRuntimeConfig: guestConfig.path,
                proxyLaunchDaemon: directory.appendingPathComponent("missing-proxy.plist").path
            )
        )

        let settings = reader.load()

        XCTAssertEqual(settings.publicHost, "settings.example.test")
        XCTAssertEqual(settings.publicPort, 8443)
        XCTAssertEqual(settings.redisBackupRetentionCount, 12)
    }

    func testConfigureArgumentsReflectSettings() {
        var settings = RuntimeSettings()
        settings.cpuCount = 2
        settings.memoryGiB = 3
        settings.diskGiB = 40
        settings.proxyPort = 18080
        settings.vitalFilesDirectory = "/data/vital"
        settings.publicHost = "public.test"
        settings.publicPort = 8080
        settings.redisBackupRetentionCount = 20
        settings.startOnBoot = false
        settings.autoRecoveryEnabled = false
        settings.preventSystemSleep = false
        settings.restartAfterSave = true

        let arguments = RuntimeCommandFactory.configureRuntimeArguments(
            settings: settings,
            adminPasswordFile: "/tmp/password"
        )

        XCTAssertEqual(arguments.first, RuntimeAdapterConstants.RuntimeCommand.runtime)
        XCTAssertTrue(arguments.contains(RuntimeAdapterConstants.RuntimeCommand.optionAdminPasswordFile))
        XCTAssertTrue(arguments.contains("/tmp/password"))
        XCTAssertTrue(arguments.contains(RuntimeAdapterConstants.RuntimeCommand.optionRestart))
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionProxyPort, in: arguments), "18080")
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionRedisBackupRetention, in: arguments), "20")
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionStartOnBoot, in: arguments), "false")
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionAutoRecovery, in: arguments), "false")
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionPreventSystemSleep, in: arguments), "false")
    }

    func testStatusReaderReportsDataDirectoryStats() throws {
        let directory = try temporaryDirectory()
        let dataDirectory = directory.appendingPathComponent("vital-files", isDirectory: true)
        let nested = dataDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 3).write(to: dataDirectory.appendingPathComponent("one.vital"))
        try Data(repeating: 1, count: 5).write(to: nested.appendingPathComponent("two.vital"))
        try Data(repeating: 1, count: 7).write(to: nested.appendingPathComponent(".hidden.vital"))

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            )
        )
        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: dataDirectory.path))

        XCTAssertEqual(status.dataDirectoryStats?.fileCount, 2)
        XCTAssertEqual(status.dataDirectoryStats?.sizeBytes, 8)
        XCTAssertNil(status.dataDirectoryStatsError)
    }

    func testStatusReaderReportsDataDirectoryStatsReadFailure() throws {
        let directory = try temporaryDirectory()
        let dataDirectory = directory.appendingPathComponent("vital-files", isDirectory: true)
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            fileStore: DataDirectoryReadFailureFileStore(readableDirectory: dataDirectory)
        )

        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: dataDirectory.path))

        XCTAssertNil(status.dataDirectoryStats)
        XCTAssertNotNil(status.dataDirectoryStatsError)
    }

    func testStatusReaderReportsDataStorageUsageReadFailure() throws {
        let directory = try temporaryDirectory()
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            storageUsageProvider: StubStorageUsageProvider(result: .failed("volume read failed"))
        )

        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: "/Volumes/Vital Files"))

        XCTAssertNil(status.dataStorage)
        XCTAssertEqual(status.dataStorageError, "volume read failed")
    }

    func testStatusReaderClearsDataStorageUsageReadFailureAfterSuccessfulRead() throws {
        let directory = try temporaryDirectory()
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            storageUsageProvider: StubStorageUsageProvider(
                result: .loaded(ResourceUsage(usedBytes: 4, totalBytes: 10))
            )
        )

        let status = reader.loadStatus(
            settings: RuntimeSettings(vitalFilesDirectory: "/Volumes/Vital Files")
        )

        XCTAssertEqual(status.dataStorage, ResourceUsage(usedBytes: 4, totalBytes: 10))
        XCTAssertNil(status.dataStorageError)
    }

    func testStatusReaderUsesConfiguredProxyPortWhenStatusDocumentDoesNotReportIt() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try """
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "status": "healthy",
          "operation": "health",
          "message": "ok",
          "updatedAt": "2026-05-26T00:01:00Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/vm",
          "runtimeVersion": "1.0.0",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": []
        }
        """.write(to: runtimeStatus, atomically: true, encoding: .utf8)
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path
            )
        )
        var settings = RuntimeSettings()
        settings.proxyPort = 19090

        let status = reader.loadStatus(settings: settings)

        XCTAssertEqual(status.proxyPort, 19090)
    }

    func testStatusReaderReportsStatusDocumentReadFailure() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try Data("not-json".utf8).write(to: runtimeStatus)

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertNil(status.runtimeState)
        XCTAssertNotNil(status.statusDocumentError)
    }

    func testStatusReaderReportsGuestRuntimeStateReadFailure() throws {
        let directory = try temporaryDirectory()
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        try Data("not-json".utf8).write(to: runtimeState)

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: runtimeState.path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertNil(status.memory)
        XCTAssertNil(status.systemDisk)
        XCTAssertNotNil(status.guestRuntimeStateError)
    }

    func testStatusReaderDoesNotInferVMStateOrErrorsWhenStatusDocumentDoesNotProvideThem() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try """
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "status": "healthy",
          "operation": "health",
          "message": "ok",
          "updatedAt": "2026-05-26T00:01:00Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/vm",
          "runtimeVersion": "1.0.0",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "vmIP": "192.168.64.33",
          "proxyPort": 19090,
          "hostProxyHTTP": "200",
          "guestHTTP": "200",
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": []
        }
        """.write(to: runtimeStatus, atomically: true, encoding: .utf8)

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertNil(status.vmState)
        XCTAssertNil(status.vmErrors)
    }

    func testObservabilityReaderUsesStatusObservationForVitalRecordersWhenSQLiteIsEmpty() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try """
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "status": "healthy",
          "operation": "health",
          "message": "ok",
          "updatedAt": "2026-05-26T00:01:00Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/vm",
          "runtimeVersion": "1.0.0",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "proxyPort": 19090,
          "hostProxyHTTP": "200",
          "guestHTTP": "200",
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": [],
          "vitalDBObservation": {
            "schemaVersion": 1,
            "source": "vitaldb-observer",
            "observedAt": "2026-05-26T00:01:00Z",
            "ready": true,
            "recorderOnlineThresholdSeconds": 60,
            "recorders": [
              {
                "vrcode": "VR_STATUS",
                "ip": "192.168.64.10",
                "lastSeenAt": "2026-05-26T00:01:00Z",
                "online": true,
                "stale": false
              }
            ],
            "beds": [],
            "devices": [],
            "filters": [],
            "proxyConnections": [],
            "anomalies": []
          }
        }
        """.write(to: runtimeStatus, atomically: true, encoding: .utf8)

        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path,
                runtimeObservabilityDB: directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB).path
            )
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.updatedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_STATUS"])
        XCTAssertEqual(history.recorders.first?.status, .online)
    }

    func testObservabilityReaderUsesGuestRuntimeStateAsCurrentObservation() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        try """
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "status": "healthy",
          "operation": "watchdog",
          "message": "ok",
          "updatedAt": "2026-05-26T00:01:00Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/vm",
          "runtimeVersion": "1.0.0",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "proxyPort": 19090,
          "hostProxyHTTP": "200",
          "guestHTTP": "200",
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": [],
          "vitalDBObservation": {
            "schemaVersion": 1,
            "source": "vitaldb-observer",
            "observedAt": "2026-05-26T00:01:00Z",
            "ready": true,
            "recorderOnlineThresholdSeconds": 60,
            "recorders": [
              {
                "vrcode": "VR_STALE_STATUS",
                "ip": "192.168.64.10",
                "lastSeenAt": "2026-05-26T00:01:00Z",
                "online": true,
                "stale": false
              }
            ],
            "beds": [],
            "devices": [],
            "filters": [],
            "proxyConnections": [],
            "anomalies": []
          }
        }
        """.write(to: runtimeStatus, atomically: true, encoding: .utf8)
        try """
        {
          "schemaVersion": 1,
          "vmIP": "192.168.64.2",
          "guestHTTP": "200",
          "updatedAt": "2026-05-26T00:01:05Z",
          "vitalDBObservation": {
            "schemaVersion": 1,
            "source": "vitaldb-observer",
            "observedAt": "2026-05-26T00:01:05Z",
            "ready": true,
            "recorderOnlineThresholdSeconds": 60,
            "recorders": [
              {
                "vrcode": "VR_FRESH_GUEST",
                "ip": "192.168.64.11",
                "lastSeenAt": "2026-05-26T00:01:05Z",
                "online": true,
                "stale": false
              }
            ],
            "beds": [],
            "devices": [],
            "filters": [],
            "proxyConnections": [],
            "anomalies": []
          }
        }
        """.write(to: runtimeState, atomically: true, encoding: .utf8)

        let paths = RuntimePaths(
            launcher: directory.appendingPathComponent("launcher").path,
            uninstaller: directory.appendingPathComponent("uninstaller").path,
            runtimeState: runtimeState.path,
            runtimeStatus: runtimeStatus.path,
            runtimeObservabilityDB: directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB).path
        )
        let statusReader = SystemRuntimeStatusReader(paths: paths)
        let observabilityReader = SystemRuntimeObservabilityReader(paths: paths)

        let status = statusReader.loadStatus(settings: RuntimeSettings())
        let history = observabilityReader.loadVitalDBRecorders()

        XCTAssertEqual(status.vitalDBObservation?.observedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.updatedAt, "2026-05-26T00:01:05Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_FRESH_GUEST"])
        XCTAssertEqual(history.recorders.first?.status, .online)
    }

    func testObservabilityReaderReportsVitalRelationshipReadFailure() throws {
        let directory = try temporaryDirectory()
        let observabilityDB = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        try Data("not-sqlite".utf8).write(to: observabilityDB)

        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeObservabilityDB: observabilityDB.path
            )
        )

        let history = reader.loadVitalDBRelationships()

        XCTAssertEqual(history.assignments, [])
        XCTAssertEqual(history.events, [])
        XCTAssertNotNil(history.readError)
        XCTAssertTrue(history.readError?.contains("assignments=") == true)
        XCTAssertTrue(history.readError?.contains("events=") == true)
    }

    func testObservabilityReaderDoesNotCreateSQLiteProjectionWhenReadingEvents() throws {
        let directory = try temporaryDirectory()
        let runtimeEvents = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let runtimeObservabilityDB = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let event = runtimeEvent(id: "jsonl-event", timestamp: "2026-05-30T00:00:00Z")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try (encoder.encode(event) + Data("\n".utf8)).write(to: runtimeEvents)
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeEvents: runtimeEvents.path,
                runtimeObservabilityDB: runtimeObservabilityDB.path
            )
        )

        let history = reader.loadRuntimeEvents(query: RuntimeEventQuery(limit: 10))

        XCTAssertEqual(history.events.map(\.id), ["jsonl-event"])
        XCTAssertEqual(history.matchingCount, 1)
        XCTAssertNotNil(history.readError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtimeObservabilityDB.path))
    }

    func testObservabilityReaderPreservesRuntimeEventReadIssueWhenServingJSONLFallback() throws {
        let directory = try temporaryDirectory()
        let runtimeEvents = directory.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let event = runtimeEvent(id: "jsonl-event", timestamp: "2026-05-30T00:00:00Z")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try (encoder.encode(event) + Data("\n".utf8)).write(to: runtimeEvents)
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeEvents: runtimeEvents.path,
                runtimeObservabilityDB: "/dev/null/events.sqlite"
            )
        )

        let history = reader.loadRuntimeEvents(query: RuntimeEventQuery(limit: 10))

        XCTAssertEqual(history.events.map(\.id), ["jsonl-event"])
        XCTAssertEqual(history.matchingCount, 1)
        XCTAssertNotNil(history.readError)
    }

    func testMacHostRuntimeClientUsesSeparateStatusAndObservabilityReaders() {
        let client = MacHostRuntimeClient(
            releaseInfo: .generated,
            statusReader: StubStatusReader(),
            observabilityReader: StubObservabilityReader()
        )

        let status = client.loadStatus(settings: RuntimeSettings())
        let events = client.loadRuntimeEvents(query: RuntimeEventQuery(limit: 1))
        let observation = client.loadVitalDBObservation()

        XCTAssertEqual(status.statusMessage, "status-reader")
        XCTAssertEqual(events.matchingCount, 7)
        XCTAssertEqual(observation?.observedAt, "2026-05-30T00:00:00Z")
    }

    func testObservabilityReaderReportsLatestObservationReadFailure() throws {
        let directory = try temporaryDirectory()
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
                runtimeObservabilityDB: "/dev/null/vital-observability.sqlite"
            )
        )

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertNotNil(snapshot.readError)
    }

    private func value(after marker: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: marker),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }

    private func runtimeEvent(id: String, timestamp: String) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: timestamp,
            product: "TiroshVitalServer",
            status: .healthy,
            previousStatus: nil,
            operation: .health,
            message: "message",
            runtimeVersion: "0.1.0",
            failureReasons: [],
            containerObservation: nil,
            progress: nil
        )
    }

    private func writeProxyLaunchDaemon(_ url: URL, proxyPort: Int) throws {
        let document = [
            "EnvironmentVariables": [
                "VITALSERVER_PROXY_PORT": "\(proxyPort)",
            ],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: document,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeSettingsReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class StubStatusReader: RuntimeStatusReading {
    func loadStatus(settings: RuntimeSettings) -> RuntimeStatus {
        RuntimeStatus(statusMessage: "status-reader")
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        RuntimeStatus(statusMessage: "status-reader-health")
    }
}

private final class StubObservabilityReader: RuntimeObservabilityReading {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory {
        loadRuntimeEvents(query: RuntimeEventQuery(limit: limit))
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory {
        RuntimeEventHistory(events: [], matchingCount: 7)
    }

    func loadVitalDBObservation() -> VitalDBObservationDocument? {
        VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )
    }

    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.fromOptional(loadVitalDBObservation())
    }

    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory {
        RuntimeVitalRecorderHistory()
    }

    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory {
        RuntimeVitalRelationshipHistory()
    }
}

private struct StubStorageUsageProvider: RuntimeStorageUsageProviding {
    let result: RuntimeStorageUsageResult

    func storageUsage(for path: String) -> RuntimeStorageUsageResult {
        result
    }
}

private final class DataDirectoryReadFailureFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let readableDirectory: URL

    init(readableDirectory: URL) {
        self.readableDirectory = readableDirectory
    }

    func fileExists(_ url: URL) -> Bool { false }
    func directoryExists(_ url: URL) -> Bool { url.path == readableDirectory.path }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoPermission) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoPermission) }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoPermission) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoPermission) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        throw CocoaError(.fileReadNoPermission)
    }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        throw CocoaError(.fileReadNoPermission)
    }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        throw CocoaError(.fileReadNoPermission)
    }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        throw CocoaError(.fileReadNoPermission)
    }
}

private final class GuestRuntimeConfigPermissionDeniedFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let guestConfig: URL

    init(guestConfig: URL) {
        self.guestConfig = guestConfig
    }

    func fileExists(_ url: URL) -> Bool { url == guestConfig }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoPermission) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoPermission) }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoSuchFile) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoSuchFile) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}

private final class SettingsReadFailureFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let existingPaths: Set<String>

    init(existingPaths: Set<String>) {
        self.existingPaths = existingPaths
    }

    func fileExists(_ url: URL) -> Bool { existingPaths.contains(url.path) }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func readData(_ url: URL) throws -> Data {
        switch url.path {
        case "/runtime/runtime-settings.json":
            throw NSError(domain: "RuntimeSettingsReaderTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "runtime settings denied",
            ])
        case "/runtime/runtime-config.json":
            throw NSError(domain: "RuntimeSettingsReaderTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "invalid legacy runtime config",
            ])
        case "/runtime/proxy.plist":
            throw NSError(domain: "RuntimeSettingsReaderTests", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "proxy plist denied",
            ])
        default:
            throw CocoaError(.fileReadNoSuchFile)
        }
    }
    func readUTF8Text(_ url: URL) throws -> String { String(decoding: try readData(url), as: UTF8.self) }
    func fileSize(_ url: URL) throws -> UInt64 {
        throw NSError(domain: "RuntimeSettingsReaderTests", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "disk size denied",
        ])
    }
    func modificationDate(_ url: URL) throws -> Date { Date(timeIntervalSince1970: 0) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}

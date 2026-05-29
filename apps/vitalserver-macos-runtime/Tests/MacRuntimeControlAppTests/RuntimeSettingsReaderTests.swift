import Contracts
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
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)

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
        try """
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "status": "healthy",
          "operation": "health",
          "message": "ok",
          "updatedAt": "2026-05-21T12:00:00Z",
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
          "failureReasons": []
        }
        """.write(to: runtimeStatus, atomically: true, encoding: .utf8)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: vmConfig.path,
                vmDisk: vmDisk.path,
                guestRuntimeConfig: guestConfig.path
            ),
            statusReader: SystemRuntimeStatusReader(
                paths: RuntimePaths(
                    launcher: directory.appendingPathComponent("launcher").path,
                    uninstaller: directory.appendingPathComponent("uninstaller").path,
                    runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                    runtimeStatus: runtimeStatus.path,
                    proxyLaunchDaemon: directory.appendingPathComponent("proxy.plist").path
                )
            )
        )

        let settings = reader.load()

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
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
                proxyLaunchDaemon: directory.appendingPathComponent("proxy.plist").path
            )
        )
        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: dataDirectory.path))

        XCTAssertEqual(status.dataDirectoryStats?.fileCount, 2)
        XCTAssertEqual(status.dataDirectoryStats?.sizeBytes, 8)
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
                runtimeStatus: runtimeStatus.path,
                proxyLaunchDaemon: directory.appendingPathComponent("proxy.plist").path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertNil(status.vmState)
        XCTAssertNil(status.vmErrors)
    }

    func testStatusReaderUsesStatusObservationForVitalRecordersWhenSQLiteIsEmpty() throws {
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

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path,
                runtimeObservabilityDB: directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB).path,
                proxyLaunchDaemon: directory.appendingPathComponent("proxy.plist").path
            )
        )

        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(history.updatedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_STATUS"])
        XCTAssertEqual(history.recorders.first?.status, .online)
    }

    func testStatusReaderDoesNotOverrideStatusObservationWithRawGuestState() throws {
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

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: runtimeState.path,
                runtimeStatus: runtimeStatus.path,
                runtimeObservabilityDB: directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB).path,
                proxyLaunchDaemon: directory.appendingPathComponent("proxy.plist").path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())
        let history = reader.loadVitalDBRecorders()

        XCTAssertEqual(status.vitalDBObservation?.observedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.updatedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_STALE_STATUS"])
        XCTAssertEqual(history.recorders.first?.status, .online)
    }

    private func value(after marker: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: marker),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeSettingsReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

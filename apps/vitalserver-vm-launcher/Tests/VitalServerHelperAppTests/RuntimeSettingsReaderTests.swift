import RuntimeCore
@testable import RuntimeControlAdapter
import XCTest
@testable import VitalServerHelperApp

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
          "autoRecoveryEnabled": false
        }
        """.write(to: vmConfig, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: vmDisk.path, contents: Data([0]))
        try """
        {
          "publicHost": "example.test",
          "publicPort": 8080
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
                    vmIPFile: directory.appendingPathComponent(RuntimeFileNames.vmIP).path,
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
        XCTAssertEqual(settings.proxyPort, 19090)
        XCTAssertFalse(settings.autoRecoveryEnabled)
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
        settings.startOnBoot = false
        settings.autoRecoveryEnabled = false
        settings.restartAfterSave = true

        let arguments = settings.configureArguments(adminPasswordFile: "/tmp/password")

        XCTAssertEqual(arguments.first, RuntimeAdapterConstants.RuntimeCommand.runtime)
        XCTAssertTrue(arguments.contains(RuntimeAdapterConstants.RuntimeCommand.optionAdminPasswordFile))
        XCTAssertTrue(arguments.contains("/tmp/password"))
        XCTAssertTrue(arguments.contains(RuntimeAdapterConstants.RuntimeCommand.optionRestart))
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionProxyPort, in: arguments), "18080")
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionStartOnBoot, in: arguments), "false")
        XCTAssertEqual(value(after: RuntimeAdapterConstants.RuntimeCommand.optionAutoRecovery, in: arguments), "false")
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

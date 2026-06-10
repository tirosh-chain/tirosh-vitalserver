import Contracts
import Application
import Domain
import RuntimeControl
@testable import OutboundAdapters
import XCTest
import Errors
@testable import MacControlPanelHost
@testable import InboundAdapters

@MainActor
final class RuntimeSettingsReaderTests: XCTestCase {
    func testLoadsInstalledSettingsFromRuntimeFiles() throws {
        let directory = try temporaryDirectory()
        let vmConfig = directory.appendingPathComponent("vm-config.json")
        let vmDisk = directory.appendingPathComponent("vm-disk.img")
        let guestSettings = directory.appendingPathComponent("runtime-settings.json")
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
          "vitalServerURL": "https://vitaldb.tirosh.ai/",
          "remoteConsoleURL": "https://console.tirosh.ai/",
          "publicHost": "example.test",
          "publicPort": 8080,
          "redisBackupRetentionCount": 30
        }
        """.write(to: guestSettings, atomically: true, encoding: .utf8)
        try writeProxyLaunchDaemon(proxyLaunchDaemon, proxyPort: 19090)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: vmConfig.path,
                vmDisk: vmDisk.path,
                guestRuntimeSettings: guestSettings.path,
                proxyLaunchDaemon: proxyLaunchDaemon.path
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues, [])
        XCTAssertEqual(settings.cpuCount, 4)
        XCTAssertEqual(settings.memoryGiB, 6)
        XCTAssertEqual(settings.diskGiB, 1)
        XCTAssertEqual(settings.minimumDiskGiB, 1)
        XCTAssertEqual(settings.bridgedInterface, "en0")
        XCTAssertEqual(settings.vitalFilesDirectory, "/Volumes/Vital Files")
        XCTAssertEqual(settings.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(settings.remoteConsoleURL, "https://console.tirosh.ai/")
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
                guestRuntimeSettings: directory.appendingPathComponent("missing-runtime-settings.json").path,
                proxyLaunchDaemon: proxyLaunchDaemon.path
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues.map(\.source), ["vmConfig", "guestRuntimeSettings", "proxyLaunchDaemon"])
        XCTAssertEqual(settings.cpuCount, RuntimeSettings().cpuCount)
        XCTAssertEqual(settings.proxyPort, RuntimeSettings().proxyPort)
    }

    func testMissingGuestRuntimeSettingsDoesNotReadSecretRuntimeConfig() throws {
        let directory = try temporaryDirectory()
        let secretGuestConfig = directory.appendingPathComponent("runtime-config.json")
        try """
        {
          "publicHost": "legacy.example.test",
          "publicPort": 8080,
          "redisBackupRetentionCount": 12
        }
        """.write(to: secretGuestConfig, atomically: true, encoding: .utf8)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: directory.appendingPathComponent("missing-vm-config.json").path,
                vmDisk: directory.appendingPathComponent("missing-disk.img").path,
                guestRuntimeSettings: directory.appendingPathComponent("missing-runtime-settings.json").path,
                proxyLaunchDaemon: directory.appendingPathComponent("missing-proxy.plist").path
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.publicHost, RuntimeSettings().publicHost)
        XCTAssertEqual(settings.publicPort, RuntimeSettings().publicPort)
        XCTAssertEqual(settings.vitalServerURL, RuntimeSettings().vitalServerURL)
        XCTAssertEqual(settings.remoteConsoleURL, RuntimeSettings().remoteConsoleURL)
        XCTAssertEqual(settings.redisBackupRetentionCount, RuntimeSettings().redisBackupRetentionCount)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "guestRuntimeSettings",
                message: "runtime settings document is missing"
            ),
        ])
    }

    func testReportsMissingVMConfigProviderFields() throws {
        let directory = try temporaryDirectory()
        let vmConfig = directory.appendingPathComponent("vm-config.json")
        let guestSettings = directory.appendingPathComponent("runtime-settings.json")
        try """
        {
          "cpuCount": 4,
          "memoryMiB": 6144,
          "network": { "mode": "bridged" }
        }
        """.write(to: vmConfig, atomically: true, encoding: .utf8)
        try writeGuestRuntimeSettings(guestSettings)
        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: vmConfig.path,
                vmDisk: directory.appendingPathComponent("missing-disk.img").path,
                guestRuntimeSettings: guestSettings.path,
                proxyLaunchDaemon: directory.appendingPathComponent("missing-proxy.plist").path
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.networkMode, .bridged)
        XCTAssertNil(settings.bridgedInterface)
        XCTAssertTrue(settings.autoRecoveryEnabled)
        XCTAssertTrue(settings.preventSystemSleep)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "vmConfig.network.bridgedInterface",
                message: "bridgedInterface is missing for bridged network mode"
            ),
            RuntimeSettingsReadIssue(
                source: "vmConfig.autoRecoveryEnabled",
                message: "autoRecoveryEnabled is missing"
            ),
            RuntimeSettingsReadIssue(
                source: "vmConfig.preventSystemSleep",
                message: "preventSystemSleep is missing"
            ),
        ])
    }

    func testReportsInvalidVMConfigNetworkMode() throws {
        let directory = try temporaryDirectory()
        let vmConfig = directory.appendingPathComponent("vm-config.json")
        let guestSettings = directory.appendingPathComponent("runtime-settings.json")
        try """
        {
          "cpuCount": 4,
          "memoryMiB": 6144,
          "network": { "mode": "invalid-mode" },
          "autoRecoveryEnabled": true,
          "preventSystemSleep": true
        }
        """.write(to: vmConfig, atomically: true, encoding: .utf8)
        try writeGuestRuntimeSettings(guestSettings)
        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: vmConfig.path,
                vmDisk: directory.appendingPathComponent("missing-disk.img").path,
                guestRuntimeSettings: guestSettings.path,
                proxyLaunchDaemon: directory.appendingPathComponent("missing-proxy.plist").path
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.networkMode, .shared)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "vmConfig.network.mode",
                message: "network mode is invalid: invalid-mode"
            ),
        ])
    }

    func testDoesNotReadSecretRuntimeConfigAsSettingsReadModel() throws {
        let guestSettings = URL(fileURLWithPath: "/missing/runtime-settings.json")
        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: "/missing/vm-config.json",
                vmDisk: "/missing/vm-disk.img",
                guestRuntimeSettings: guestSettings.path,
                proxyLaunchDaemon: "/missing/proxy.plist"
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertFalse(settings.readIssues.contains { $0.source == "guestRuntimeConfig" })
        XCTAssertTrue(settings.readIssues.contains { $0.source == "guestRuntimeSettings" })
        XCTAssertEqual(settings.publicHost, RuntimeSettings().publicHost)
        XCTAssertEqual(settings.publicPort, RuntimeSettings().publicPort)
    }

    func testReportsSettingsReadFailuresForNonSecretRuntimeFiles() {
        let paths = RuntimeSettingsPaths(
            vmConfig: "/missing/vm-config.json",
            vmDisk: "/runtime/vm-disk.img",
            guestRuntimeSettings: "/runtime/runtime-settings.json",
            proxyLaunchDaemon: "/runtime/proxy.plist"
        )
        let reader = SystemRuntimeSettingsReader(
            paths: paths,
            fileStore: SettingsReadFailureFileStore(existingPaths: [
                paths.vmDisk,
                paths.guestRuntimeSettings,
                paths.proxyLaunchDaemon,
            ]),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues.map(\.source), [
            "vmDisk",
            "guestRuntimeSettings",
            "proxyLaunchDaemon",
        ])
        XCTAssertTrue(settings.readIssues[0].message.contains("disk size denied"))
        XCTAssertTrue(settings.readIssues[1].message.contains("runtime settings denied"))
        XCTAssertTrue(settings.readIssues[2].message.contains("proxy plist denied"))
    }

    func testReportsSettingsPathInspectionFailures() {
        let paths = RuntimeSettingsPaths(
            vmConfig: "/runtime/vm-config.json",
            vmDisk: "/runtime/vm-disk.img",
            guestRuntimeSettings: "/runtime/runtime-settings.json",
            proxyLaunchDaemon: "/runtime/proxy.plist"
        )
        let reader = SystemRuntimeSettingsReader(
            paths: paths,
            fileStore: DataDirectoryPathStateFileStore(pathStates: [
                paths.vmConfig: .inspectFailed("vm config denied"),
                paths.vmDisk: .inspectFailed("disk denied"),
                paths.guestRuntimeSettings: .inspectFailed("runtime settings denied"),
                paths.proxyLaunchDaemon: .inspectFailed("proxy plist denied"),
            ]),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "vmConfig",
                message: "path inspection failed path=/runtime/vm-config.json reason=vm config denied"
            ),
            RuntimeSettingsReadIssue(
                source: "vmDisk",
                message: "path inspection failed path=/runtime/vm-disk.img reason=disk denied"
            ),
            RuntimeSettingsReadIssue(
                source: "guestRuntimeSettings",
                message: "path inspection failed path=/runtime/runtime-settings.json reason=runtime settings denied"
            ),
            RuntimeSettingsReadIssue(
                source: "proxyLaunchDaemon",
                message: "path inspection failed path=/runtime/proxy.plist reason=proxy plist denied"
            ),
        ])
    }

    func testReportsUnexpectedSettingsPathStates() {
        let paths = RuntimeSettingsPaths(
            vmConfig: "/runtime/vm-config.json",
            vmDisk: "/runtime/vm-disk.img",
            guestRuntimeSettings: "/runtime/runtime-settings.json",
            proxyLaunchDaemon: "/runtime/proxy.plist"
        )
        let reader = SystemRuntimeSettingsReader(
            paths: paths,
            fileStore: DataDirectoryPathStateFileStore(pathStates: [
                paths.vmConfig: .directory,
                paths.vmDisk: .other("symbolic-link"),
                paths.guestRuntimeSettings: .unknown("stale-provider-state"),
                paths.proxyLaunchDaemon: .directory,
            ]),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "vmConfig",
                message: "path state is unexpected path=/runtime/vm-config.json state=directory"
            ),
            RuntimeSettingsReadIssue(
                source: "vmDisk",
                message: "path state is unexpected path=/runtime/vm-disk.img state=other: symbolic-link"
            ),
            RuntimeSettingsReadIssue(
                source: "guestRuntimeSettings",
                message: "path state is unexpected path=/runtime/runtime-settings.json state=stale-provider-state"
            ),
            RuntimeSettingsReadIssue(
                source: "proxyLaunchDaemon",
                message: "path state is unexpected path=/runtime/proxy.plist state=directory"
            ),
        ])
    }

    func testReportsStartOnBootLaunchctlReadFailure() {
        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: "/missing/vm-config.json",
                vmDisk: "/missing/vm-disk.img",
                guestRuntimeSettings: "/missing/runtime-settings.json",
                proxyLaunchDaemon: "/missing/proxy.plist"
            ),
            runCommand: { executable, arguments in
                XCTAssertEqual(executable, RuntimeControlClientConstants.Commands.launchctl)
                XCTAssertEqual(arguments, ["print-disabled", "system"])
                return RuntimeCommandResult(exitCode: 1, stdout: "", stderr: "launchctl denied")
            }
        )

        let settings = reader.load()

        XCTAssertFalse(settings.startOnBootConfigurable)
        XCTAssertEqual(settings.readIssues, [
            RuntimeSettingsReadIssue(
                source: "guestRuntimeSettings",
                message: "runtime settings document is missing"
            ),
            RuntimeSettingsReadIssue(source: "startOnBoot", message: "launchctl denied"),
        ])
    }

    func testLoadsGuestRuntimeSettingsFromCurrentReadModel() throws {
        let directory = try temporaryDirectory()
        let guestSettings = directory.appendingPathComponent("runtime-settings.json")
        try """
        {
          "vitalServerURL": "https://settings.example.test/",
          "remoteConsoleURL": "https://console.settings.example.test/",
          "publicHost": "settings.example.test",
          "publicPort": 8443,
          "redisBackupRetentionCount": 12
        }
        """.write(to: guestSettings, atomically: true, encoding: .utf8)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: directory.appendingPathComponent("missing-vm-config.json").path,
                vmDisk: directory.appendingPathComponent("missing-disk.img").path,
                guestRuntimeSettings: guestSettings.path,
                proxyLaunchDaemon: directory.appendingPathComponent("missing-proxy.plist").path
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.publicHost, "settings.example.test")
        XCTAssertEqual(settings.publicPort, 8443)
        XCTAssertEqual(settings.vitalServerURL, "https://settings.example.test/")
        XCTAssertEqual(settings.remoteConsoleURL, "https://console.settings.example.test/")
        XCTAssertEqual(settings.redisBackupRetentionCount, 12)
    }

    func testReportsOutOfRangeGuestRuntimeBackupRetention() throws {
        let directory = try temporaryDirectory()
        let guestSettings = directory.appendingPathComponent("runtime-settings.json")
        try writeGuestRuntimeSettings(guestSettings, redisBackupRetentionCount: 31)

        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: directory.appendingPathComponent("missing-vm-config.json").path,
                vmDisk: directory.appendingPathComponent("missing-disk.img").path,
                guestRuntimeSettings: guestSettings.path,
                proxyLaunchDaemon: directory.appendingPathComponent("missing-proxy.plist").path
            ),
            runCommand: startOnBootCommand()
        )

        let settings = reader.load()

        XCTAssertEqual(settings.redisBackupRetentionCount, 30)
        XCTAssertTrue(settings.readIssues.contains(RuntimeSettingsReadIssue(
            source: "guestRuntimeSettings.redisBackupRetentionCount",
            message: "redisBackupRetentionCount is out of range: 31"
        )))
    }

    func testConfigureArgumentsReflectSettings() {
        var settings = RuntimeSettings()
        settings.cpuCount = 2
        settings.memoryGiB = 3
        settings.diskGiB = 40
        settings.proxyPort = 18080
        settings.vitalFilesDirectory = "/data/vital"
        settings.vitalServerURL = "https://vitaldb.tirosh.ai/"
        settings.remoteConsoleURL = "https://console.tirosh.ai/"
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

        XCTAssertEqual(arguments.first, RuntimeControlClientConstants.RuntimeCommand.runtime)
        XCTAssertTrue(arguments.contains(RuntimeControlClientConstants.RuntimeCommand.optionAdminPasswordFile))
        XCTAssertTrue(arguments.contains("/tmp/password"))
        XCTAssertTrue(arguments.contains(RuntimeControlClientConstants.RuntimeCommand.optionRestart))
        XCTAssertEqual(value(after: RuntimeControlClientConstants.RuntimeCommand.optionProxyPort, in: arguments), "18080")
        XCTAssertEqual(value(after: RuntimeControlClientConstants.RuntimeCommand.optionVitalServerURL, in: arguments), "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(value(after: RuntimeControlClientConstants.RuntimeCommand.optionRemoteConsoleURL, in: arguments), "https://console.tirosh.ai/")
        XCTAssertEqual(value(after: RuntimeControlClientConstants.RuntimeCommand.optionRedisBackupRetention, in: arguments), "20")
        XCTAssertEqual(value(after: RuntimeControlClientConstants.RuntimeCommand.optionStartOnBoot, in: arguments), "false")
        XCTAssertEqual(value(after: RuntimeControlClientConstants.RuntimeCommand.optionAutoRecovery, in: arguments), "false")
        XCTAssertEqual(value(after: RuntimeControlClientConstants.RuntimeCommand.optionPreventSystemSleep, in: arguments), "false")
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

    func testStatusReaderReportsMissingDataDirectoryRoot() throws {
        let directory = try temporaryDirectory()
        let dataDirectory = directory.appendingPathComponent("vital-files", isDirectory: true)
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            fileStore: DataDirectoryPathStateFileStore(pathStates: [dataDirectory.path: .missing])
        )

        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: dataDirectory.path))

        XCTAssertNil(status.dataDirectoryStats)
        XCTAssertEqual(status.dataDirectoryStatsError, "data directory missing path=\(dataDirectory.path)")
    }

    func testStatusReaderReportsDataDirectoryRootInspectionFailure() throws {
        let directory = try temporaryDirectory()
        let dataDirectory = directory.appendingPathComponent("vital-files", isDirectory: true)
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            fileStore: DataDirectoryPathStateFileStore(
                pathStates: [dataDirectory.path: .inspectFailed("permission denied")]
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: dataDirectory.path))

        XCTAssertNil(status.dataDirectoryStats)
        XCTAssertEqual(
            status.dataDirectoryStatsError,
            "data directory path inspection failed path=\(dataDirectory.path) reason=permission denied"
        )
    }

    func testStatusReaderReportsUnexpectedDataDirectoryRootState() throws {
        let directory = try temporaryDirectory()
        let dataDirectory = directory.appendingPathComponent("vital-files")
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            fileStore: DataDirectoryPathStateFileStore(
                pathStates: [dataDirectory.path: .file]
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: dataDirectory.path))

        XCTAssertNil(status.dataDirectoryStats)
        XCTAssertEqual(
            status.dataDirectoryStatsError,
            "data directory path state is unexpected path=\(dataDirectory.path) state=file"
        )
    }

    func testStatusReaderReportsListedDataDirectoryEntryMissingDuringTraversal() throws {
        let directory = try temporaryDirectory()
        let dataDirectory = directory.appendingPathComponent("vital-files", isDirectory: true)
        let staleEntry = dataDirectory.appendingPathComponent("stale.vital")
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            fileStore: DataDirectoryPathStateFileStore(
                pathStates: [
                    dataDirectory.path: .directory,
                    staleEntry.path: .missing,
                ],
                directoryContents: [
                    dataDirectory.path: [staleEntry],
                ]
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings(vitalFilesDirectory: dataDirectory.path))

        XCTAssertNil(status.dataDirectoryStats)
        XCTAssertEqual(
            status.dataDirectoryStatsError,
            "data directory listed path is missing during traversal path=\(staleEntry.path)"
        )
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

    func testStatusReaderReportsMissingRuntimeDocumentsAsReadIssues() throws {
        let directory = try temporaryDirectory()
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertEqual(status.readIssues.map(\.source), ["runtimeStatus", "guestRuntimeState"])
        XCTAssertNil(status.statusDocumentError)
        XCTAssertNil(status.guestRuntimeStateError)
    }

    func testStatusReaderPreservesGuestRuntimeStateInspectionFailure() throws {
        let directory = try temporaryDirectory()
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: runtimeState.path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            fileStore: DataDirectoryPathStateFileStore(pathStates: [
                runtimeState.path: .inspectFailed("permission denied"),
            ])
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertEqual(
            status.guestRuntimeStateError,
            "guest runtime state path inspection failed path=\(runtimeState.path) reason=permission denied"
        )
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "guestRuntimeState"
                && $0.message == status.guestRuntimeStateError
        })
    }

    func testStatusReaderPreservesRuntimeStatusInspectionFailure() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path
            ),
            fileStore: DataDirectoryPathStateFileStore(pathStates: [
                runtimeStatus.path: .inspectFailed("permission denied"),
            ])
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertEqual(
            status.statusDocumentError,
            "runtime status document path inspection failed path=\(runtimeStatus.path) reason=permission denied"
        )
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "runtimeStatus"
                && $0.message == status.statusDocumentError
        })
    }

    func testStatusReaderPreservesUnexpectedGuestRuntimeStatePathState() throws {
        let directory = try temporaryDirectory()
        let runtimeState = directory.appendingPathComponent(RuntimeFileNames.runtimeState)
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: runtimeState.path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            fileStore: DataDirectoryPathStateFileStore(pathStates: [
                runtimeState.path: .directory,
            ])
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertEqual(
            status.guestRuntimeStateError,
            "guest runtime state path state is unexpected path=\(runtimeState.path) state=directory"
        )
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "guestRuntimeState"
                && $0.message == status.guestRuntimeStateError
        })
    }

    func testStatusReaderPreservesRuntimeLauncherInspectionFailure() throws {
        let directory = try temporaryDirectory()
        let launcher = directory.appendingPathComponent("launcher")
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: launcher.path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            runtimeExecutableState: { _ in .inspectFailed("permission denied") }
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertFalse(status.runtimeInstalled)
        XCTAssertEqual(status.runtimeInstallationState, .inspectFailed("permission denied"))
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "runtimeInstallation"
                && $0.message == "runtime launcher inspection failed path=\(launcher.path) reason=permission denied"
        })
    }

    func testStatusReaderPreservesPresentButNonExecutableRuntimeLauncher() throws {
        let directory = try temporaryDirectory()
        let launcher = directory.appendingPathComponent("launcher")
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: launcher.path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            runtimeExecutableState: { _ in .present }
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertFalse(status.runtimeInstalled)
        XCTAssertEqual(status.runtimeInstallationState, .present)
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "runtimeInstallation"
                && $0.message == "runtime launcher is present but not executable path=\(launcher.path)"
        })
    }

    func testStatusReaderPreservesMissingProxyPortWithoutSettingsFallback() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try """
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
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
        var settings = RuntimeSettings()
        settings.proxyPort = 19090

        let status = reader.loadStatus(settings: settings)

        XCTAssertNil(status.proxyPort)
        XCTAssertNil(status.statusDocumentError)
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "proxyPort"
                && $0.message == "proxy port is missing from runtime status document"
        })
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
        XCTAssertTrue(status.readIssues.contains { $0.source == "runtimeStatus" })
    }

    func testStatusReaderLoadsRuntimeInstallStateDocumentSeparatelyFromRuntimeStatus() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        let runtimeInstallState = directory.appendingPathComponent(RuntimeFileNames.runtimeInstallState)
        try """
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
          "status": "initializing",
          "operation": "watchdog",
          "message": "watchdog recovery deferred",
          "updatedAt": "2026-06-09T14:09:32Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/vm",
          "runtimeVersion": "1.0.0",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "hostProxyHTTP": "000failed",
          "guestHTTP": "000failed",
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": []
        }
        """.write(to: runtimeStatus, atomically: true, encoding: .utf8)
        try """
        {
          "schemaVersion": 1,
          "state": "provisioned",
          "mode": "provision",
          "updatedAt": "2026-06-09T14:06:25Z",
          "message": "runtime install provisioned",
          "blockers": []
        }
        """.write(to: runtimeInstallState, atomically: true, encoding: .utf8)

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path,
                runtimeInstallState: runtimeInstallState.path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertEqual(status.runtimeState, .initializing)
        XCTAssertNil(status.statusDocumentError)
        XCTAssertEqual(status.installStateDocument?.state, .provisioned)
        XCTAssertEqual(status.installStateDocument?.mode, .provision)
        XCTAssertNil(status.installStateDocumentError)
        XCTAssertTrue(RuntimeActiveOperationPolicy.isInitializationInProgress(status))
    }

    func testStatusReaderReportsRuntimeInstallStateReadFailure() throws {
        let directory = try temporaryDirectory()
        let runtimeInstallState = directory.appendingPathComponent(RuntimeFileNames.runtimeInstallState)
        try Data("not-json".utf8).write(to: runtimeInstallState)

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
                runtimeInstallState: runtimeInstallState.path
            )
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertNil(status.installStateDocument)
        XCTAssertNotNil(status.installStateDocumentError)
        XCTAssertTrue(status.readIssues.contains { $0.source == "runtimeInstallState" })
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
        XCTAssertTrue(status.readIssues.contains { $0.source == "guestRuntimeState" })
    }

    func testStatusReaderDoesNotInferVMStateOrErrorsWhenStatusDocumentDoesNotProvideThem() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try """
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
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

    func testStatusReaderPreservesLaunchdReadFailureAsServiceStateIssue() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try writeRuntimeStatusDocument(
            runtimeStatus,
            extraFields: """
              "vmService": "loaded",
              "proxyService": "loaded",
              "watchdogService": "loaded",
            """
        )

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path
            ),
            runSyncCommand: { _, _ in
                RuntimeCommandResult(exitCode: 1, stdout: "", stderr: "Operation not permitted")
            }
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertEqual(status.vmServiceState, .loaded)
        XCTAssertEqual(status.proxyServiceState, .loaded)
        XCTAssertEqual(status.watchdogServiceState, .loaded)
        XCTAssertEqual(status.vmServiceStateSource, .statusDocument)
        XCTAssertEqual(status.proxyServiceStateSource, .statusDocument)
        XCTAssertEqual(status.watchdogServiceStateSource, .statusDocument)
        XCTAssertEqual(status.guestLogSyncServiceState, .permissionDenied("exitCode=1 stderr=Operation not permitted"))
        XCTAssertEqual(status.guestLogSyncServiceStateSource, .liveLaunchd)
        XCTAssertEqual(status.sleepPreventionServiceStateSource, .liveLaunchd)
        XCTAssertFalse(status.guestLogSyncServiceLoaded)
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "guestLogSyncService"
                && $0.message == "exitCode=1 stderr=Operation not permitted"
        })
    }

    func testStatusReaderMarksServiceStatesAsLiveLaunchdWhenStatusDocumentIsMissing() throws {
        let directory = try temporaryDirectory()
        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: directory.appendingPathComponent(RuntimeFileNames.runtimeStatus).path
            ),
            runSyncCommand: { _, _ in
                RuntimeCommandResult(exitCode: 1, stdout: "", stderr: "Could not find service")
            }
        )

        let status = reader.loadStatus(settings: RuntimeSettings())

        XCTAssertEqual(status.vmServiceStateSource, .liveLaunchd)
        XCTAssertEqual(status.proxyServiceStateSource, .liveLaunchd)
        XCTAssertEqual(status.guestLogSyncServiceStateSource, .liveLaunchd)
        XCTAssertEqual(status.sleepPreventionServiceStateSource, .liveLaunchd)
        XCTAssertEqual(status.watchdogServiceStateSource, .liveLaunchd)
    }

    func testHealthStatusPreservesHTTPProbeReadFailureAsStatusReadIssue() async throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try writeRuntimeStatusDocument(
            runtimeStatus,
            extraFields: """
              "vmService": "loaded",
              "proxyService": "loaded",
              "watchdogService": "loaded",
              "vmIP": "192.168.64.33",
            """
        )

        let reader = SystemRuntimeStatusReader(
            paths: RuntimePaths(
                launcher: directory.appendingPathComponent("launcher").path,
                uninstaller: directory.appendingPathComponent("uninstaller").path,
                runtimeState: directory.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: runtimeStatus.path
            ),
            runCommand: { _, _ in
                RuntimeCommandResult(exitCode: 28, stdout: "", stderr: "Operation timed out")
            },
            runSyncCommand: { _, _ in
                RuntimeCommandResult(exitCode: 1, stdout: "", stderr: "Could not find service")
            }
        )

        let status = await reader.loadHealthStatus(settings: RuntimeSettings())

        XCTAssertNil(status.guestHTTP)
        XCTAssertNil(status.hostProxyHTTP)
        XCTAssertNil(status.redisUIHTTP)
        XCTAssertNil(status.swaggerUIHTTP)
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "guestHTTP"
                && $0.message == "exitCode=28 stderr=Operation timed out"
        })
        XCTAssertTrue(status.readIssues.contains {
            $0.source == "hostProxyHTTP"
                && $0.message == "exitCode=28 stderr=Operation timed out"
        })
    }

    func testObservabilityReaderUsesStatusObservationForVitalRecordersWhenSQLiteIsEmpty() throws {
        let directory = try temporaryDirectory()
        let runtimeStatus = directory.appendingPathComponent(RuntimeFileNames.runtimeStatus)
        try """
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
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

        let reader = SystemRuntimeObservabilityReader.live(
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
          "product": "VitalServerHelper",
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
        let observabilityReader = SystemRuntimeObservabilityReader.live(paths: paths)

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

        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeObservabilityDB: observabilityDB.path
            )
        )

        let history = reader.loadVitalDBRelationships()

        XCTAssertEqual(history.state, .readFailed)
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
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeEvents: runtimeEvents.path,
                runtimeObservabilityDB: runtimeObservabilityDB.path
            )
        )

        let history = reader.loadRuntimeEvents(query: RuntimeEventQuery(limit: 10))

        XCTAssertEqual(history.state, .partiallyLoaded)
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
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeEvents: runtimeEvents.path,
                runtimeObservabilityDB: "/dev/null/events.sqlite"
            )
        )

        let history = reader.loadRuntimeEvents(query: RuntimeEventQuery(limit: 10))

        XCTAssertEqual(history.state, .partiallyLoaded)
        XCTAssertEqual(history.events.map(\.id), ["jsonl-event"])
        XCTAssertEqual(history.matchingCount, 1)
        XCTAssertNotNil(history.readError)
    }

    func testMacRuntimeControlClientUsesSeparateStatusAndObservabilityReaders() {
        let client = MacRuntimeControlClient(
            releaseInfo: .generated,
            statusReader: StubStatusReader(),
            observabilityReader: StubObservabilityReader()
        )

        let status = client.loadStatus(settings: RuntimeSettings())
        let events = client.loadRuntimeEvents(query: RuntimeEventQuery(limit: 1))
        let observation = client.loadVitalDBObservationSnapshot().observation

        XCTAssertEqual(status.statusMessage, "status-reader")
        XCTAssertEqual(events.matchingCount, 7)
        XCTAssertEqual(observation?.observedAt, "2026-05-30T00:00:00Z")
    }

    func testObservabilityReaderReportsLatestObservationReadFailure() throws {
        let directory = try temporaryDirectory()
        let reader = SystemRuntimeObservabilityReader.live(
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

    private func startOnBootCommand(
        stdout: String = ""
    ) -> @Sendable (String, [String]) -> RuntimeCommandResult {
        { _, _ in RuntimeCommandResult(exitCode: 0, stdout: stdout, stderr: "") }
    }

    private func runtimeEvent(id: String, timestamp: String) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: .statusChanged,
            timestamp: timestamp,
            product: "VitalServerHelper",
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

    private func writeRuntimeStatusDocument(_ url: URL, extraFields: String) throws {
        try """
        {
          "schemaVersion": 2,
          "product": "VitalServerHelper",
          "status": "healthy",
          "operation": "health",
          "message": "ok",
          "updatedAt": "2026-05-26T00:01:00Z",
          "productRoot": "/tmp/product",
          "runtimeHome": "/tmp/vm",
          "runtimeVersion": "1.0.0",
          "proxyPort": 19090,
          "hostProxyHTTP": "200",
          "guestHTTP": "200",
        \(extraFields)
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": []
        }
        """.write(to: url, atomically: true, encoding: .utf8)
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

    private func writeGuestRuntimeSettings(
        _ url: URL,
        vitalServerURL: String = "https://vitaldb.tirosh.ai/",
        remoteConsoleURL: String = "https://console.tirosh.ai/",
        publicHost: String = "vitaldb.tirosh.ai",
        publicPort: Int = 443,
        redisBackupRetentionCount: Int = 20
    ) throws {
        try """
        {
          "vitalServerURL": "\(vitalServerURL)",
          "remoteConsoleURL": "\(remoteConsoleURL)",
          "publicHost": "\(publicHost)",
          "publicPort": \(publicPort),
          "redisBackupRetentionCount": \(redisBackupRetentionCount)
        }
        """.write(to: url, atomically: true, encoding: .utf8)
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

private final class DataDirectoryPathStateFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let pathStates: [String: RuntimePathState]
    private let directoryContents: [String: [URL]]
    private let fileSizes: [String: UInt64]

    init(
        pathStates: [String: RuntimePathState],
        directoryContents: [String: [URL]] = [:],
        fileSizes: [String: UInt64] = [:]
    ) {
        self.pathStates = pathStates
        self.directoryContents = directoryContents
        self.fileSizes = fileSizes
    }

    func fileExists(_ url: URL) -> Bool {
        pathStates[url.path] == .file
    }

    func directoryExists(_ url: URL) -> Bool {
        pathStates[url.path] == .directory
    }

    func isExecutableFile(atPath path: String) -> Bool { false }

    func fileState(atPath path: String) -> RuntimeFileState {
        fileState(at: URL(fileURLWithPath: path))
    }

    func fileState(at url: URL) -> RuntimeFileState {
        switch pathState(at: url) {
        case .file, .directory, .other:
            .present
        case .missing:
            .missing
        case .inspectFailed(let reason):
            .inspectFailed(reason)
        case .unknown(let value):
            .unknown(value)
        }
    }

    func pathState(at url: URL) -> RuntimePathState {
        pathStates[url.path] ?? .missing
    }

    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoSuchFile) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoSuchFile) }

    func fileSize(_ url: URL) throws -> UInt64 {
        guard let size = fileSizes[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return size
    }

    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoSuchFile) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}

    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        guard let contents = directoryContents[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return contents
    }

    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        []
    }

    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        throw CocoaError(.fileReadNoSuchFile)
    }

    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        throw CocoaError(.fileReadNoSuchFile)
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

import Contracts
import Foundation
import Workflow
import XCTest

final class RuntimeConfigureWorkflowTests: XCTestCase {
    func testConfiguresRuntimeDocumentsAndRunsRequestedPorts() throws {
        let harness = Harness()

        let result = try harness.workflow.configure(RuntimeConfigureWorkflowInput(
            changes: [
                .cpu(4),
                .memoryGiB(8),
                .diskGiB(64),
                .network(.shared),
                .proxyPort(18080),
                .vitalFilesDirectory(URL(fileURLWithPath: "/data/vital-files")),
                .publicHost("stale.example"),
                .publicPort(8080),
                .vitalServerURL("https://vitaldb.tirosh.ai/"),
                .remoteConsoleURL("https://console.tirosh.ai/"),
                .adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password")),
                .startOnBoot(false),
                .autoRecovery(false),
                .preventSystemSleep(false),
                .redisBackupRetention(20),
            ],
            restart: true
        ))

        XCTAssertTrue(result.restart)
        XCTAssertEqual(harness.resizedDisks, [64])
        XCTAssertEqual(harness.proxyPorts, [18080])
        XCTAssertEqual(harness.createdDirectories, [URL(fileURLWithPath: "/data/vital-files")])
        XCTAssertEqual(harness.startOnBootValues, [false])
        XCTAssertEqual(harness.systemSleepPreventionValues, [false])
        XCTAssertEqual(harness.restrictedFiles, [harness.guestConfigURL])
        XCTAssertEqual(harness.restartCount, 1)

        let vmConfig = try harness.savedVMConfig()
        XCTAssertEqual(vmConfig.configureCPUCount, 4)
        XCTAssertEqual(vmConfig.configureMemoryMiB, 8192)
        XCTAssertEqual(vmConfig.configureNetworkMode, .shared)
        XCTAssertNil(vmConfig.configureBridgedInterface)
        XCTAssertEqual(vmConfig.vitalFilesDirectory?.hostPath, "/data/vital-files")
        XCTAssertEqual(vmConfig.configureAutoRecoveryEnabled, false)
        XCTAssertEqual(vmConfig.configurePreventSystemSleep, false)

        let guestConfig = try harness.savedGuestConfig()
        XCTAssertEqual(guestConfig.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(guestConfig.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(guestConfig.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(guestConfig.publicPort, 443)
        XCTAssertEqual(guestConfig.adminPassword, "secret")
        XCTAssertEqual(guestConfig.vitalFilesDirectory, "/mnt/vital-files")
        XCTAssertEqual(guestConfig.redisBackupRetentionCount, 20)

        let settings = try harness.savedGuestSettings()
        XCTAssertEqual(settings.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(settings.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(settings.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(settings.publicPort, 443)
        XCTAssertEqual(settings.redisBackupRetentionCount, 20)
    }

    func testRejectsInvalidAdvertisedURL() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.workflow.configure(RuntimeConfigureWorkflowInput(
            changes: [.vitalServerURL("vitaldb.tirosh.ai")]
        ))) { error in
            XCTAssertEqual(
                error as? RuntimeConfigureWorkflowError,
                .invalidArgument("--vitalserver-url must be an absolute http/https URL")
            )
        }
    }

    func testRejectsEmptyAdvertisedURL() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.workflow.configure(RuntimeConfigureWorkflowInput(
            changes: [.remoteConsoleURL("")]
        ))) { error in
            XCTAssertEqual(
                error as? RuntimeConfigureWorkflowError,
                .invalidArgument("--remote-console-url must be an absolute http/https URL")
            )
        }
    }

    func testVitalServerHTTPURLWithoutExplicitPortUsesDefaultPublicPort() throws {
        let harness = Harness()

        _ = try harness.workflow.configure(RuntimeConfigureWorkflowInput(
            changes: [
                .publicPort(8080),
                .vitalServerURL("http://vitaldb.tirosh.ai/"),
            ]
        ))

        let guestConfig = try harness.savedGuestConfig()
        XCTAssertEqual(guestConfig.vitalServerURL, "http://vitaldb.tirosh.ai/")
        XCTAssertEqual(guestConfig.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(guestConfig.publicPort, 80)
    }

    func testRejectsBridgedModeWithoutInterface() {
        let harness = Harness()
        harness.vmConfig.configureBridgedInterface = nil

        XCTAssertThrowsError(try harness.workflow.configure(RuntimeConfigureWorkflowInput(
            changes: [.network(.bridged)]
        ))) { error in
            XCTAssertEqual(
                error as? RuntimeConfigureWorkflowError,
                .invalidArgument("--bridged-interface is required when --network bridged")
            )
        }
    }

    final class Harness {
        let vmConfigURL = URL(fileURLWithPath: "/runtime/vm-config.json")
        let guestConfigURL = URL(fileURLWithPath: "/runtime/runtime-config.json")
        let guestSettingsURL = URL(fileURLWithPath: "/runtime/runtime-settings.json")
        lazy var workflow: RuntimeConfigureWorkflow<ConfigureTestVMConfig> = RuntimeConfigureWorkflow(
            context: RuntimeConfigureWorkflowContext(
                vmConfigURL: vmConfigURL,
                guestRuntimeConfigURL: guestConfigURL,
                guestRuntimeSettingsURL: guestSettingsURL,
                minimumCPUCount: 2,
                maximumAllowedCPUCount: 8,
                minimumMemoryGiB: 4,
                maximumAllowedMemoryGiB: 16,
                memoryStepGiB: 4,
                minimumDiskGiB: 4,
                maximumDiskGiB: 128,
                diskStepGiB: 4,
                maximumRedisBackupRetentionCount: 30,
                defaultPublicPort: 80,
                sharedNetworkMode: .shared,
                bridgedNetworkMode: .bridged,
                vitalFilesDirectoryTag: "vital-files",
                vitalFilesDirectoryGuestMountPath: "/mnt/vital-files"
            ),
            operations: RuntimeConfigureWorkflowOperations(
                loadVMConfig: { [unowned self] _ in vmConfig },
                loadGuestRuntimeConfig: { [unowned self] _ in guestConfig },
                encodeVMConfig: { config in try JSONEncoder().encode(config) },
                encodeGuestRuntimeConfig: { config in try JSONEncoder().encode(config) },
                encodeGuestRuntimeSettings: { settings in try JSONEncoder().encode(settings) },
                writeData: { [unowned self] data, url, _ in writes[url] = data },
                createDirectory: { [unowned self] url, _ in createdDirectories.append(url) },
                resizeVMDiskIfNeeded: { [unowned self] diskGiB in resizedDisks.append(diskGiB) },
                setInstalledProxyPort: { [unowned self] port in proxyPorts.append(port) },
                readSecretFile: { _ in "secret" },
                restrictSecretFile: { [unowned self] url in restrictedFiles.append(url) },
                setStartOnBoot: { [unowned self] enabled in startOnBootValues.append(enabled) },
                setSystemSleepPrevention: { [unowned self] enabled in
                    systemSleepPreventionValues.append(enabled)
                },
                restartRuntimeServices: { [unowned self] in restartCount += 1 },
                ensureRuntimeDefaults: { _ in },
                log: { _ in }
            )
        )

        var vmConfig = ConfigureTestVMConfig(
            configureCPUCount: 2,
            configureMemoryMiB: 4096,
            configureNetworkMode: .bridged,
            configureBridgedInterface: "en0",
            configureAutoRecoveryEnabled: true,
            configurePreventSystemSleep: true
        )
        var guestConfig = GuestRuntimeConfigDocument(
            vitalserverHttpPort: 18080,
            redisHost: "redis",
            redisPort: 6379,
            trustProxy: true,
            vitalServerURL: "",
            remoteConsoleURL: "",
            publicHost: "",
            publicPort: 80,
            adminPassword: "admin",
            vitalFilesDirectory: "/mnt/old",
            redisBackupRetentionCount: 30,
            redisUiPort: 18081,
            swaggerUiPort: 18082,
            testkitEnabled: false
        )
        var writes: [URL: Data] = [:]
        var createdDirectories: [URL] = []
        var resizedDisks: [Int] = []
        var proxyPorts: [Int] = []
        var restrictedFiles: [URL] = []
        var startOnBootValues: [Bool] = []
        var systemSleepPreventionValues: [Bool] = []
        var restartCount = 0

        func savedVMConfig() throws -> ConfigureTestVMConfig {
            try JSONDecoder().decode(ConfigureTestVMConfig.self, from: XCTUnwrap(writes[vmConfigURL]))
        }

        func savedGuestConfig() throws -> GuestRuntimeConfigDocument {
            try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: XCTUnwrap(writes[guestConfigURL]))
        }

        func savedGuestSettings() throws -> GuestRuntimeSettingsDocument {
            try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: XCTUnwrap(writes[guestSettingsURL]))
        }
    }
}

enum ConfigureTestNetworkMode: String, Codable, Equatable {
    case shared
    case bridged
}

struct ConfigureTestSharedDirectory: Codable, Equatable {
    var hostPath: String
    var tag: String
    var guestMountPath: String
    var readOnly: Bool
}

struct ConfigureTestVMConfig: Codable, Equatable, RuntimeConfigureMutableVMRuntimeConfiguration {
    var configureCPUCount: Int
    var configureMemoryMiB: UInt64
    var configureNetworkMode: ConfigureTestNetworkMode
    var configureBridgedInterface: String?
    var configureAutoRecoveryEnabled: Bool?
    var configurePreventSystemSleep: Bool?
    var vitalFilesDirectory: ConfigureTestSharedDirectory?

    mutating func setConfigureVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        vitalFilesDirectory = ConfigureTestSharedDirectory(
            hostPath: directory.hostPath,
            tag: directory.tag,
            guestMountPath: directory.guestMountPath,
            readOnly: directory.readOnly
        )
    }
}

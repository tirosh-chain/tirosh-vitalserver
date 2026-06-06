import Application
import Contracts
import Foundation
import XCTest
import Errors

final class ConfigureRuntimeUseCaseTests: XCTestCase {
    func testPlansRuntimeDocumentsAndExplicitEffectsFromCurrentState() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(
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
                    .adminPassword("secret"),
                    .startOnBoot(false),
                    .autoRecovery(false),
                    .preventSystemSleep(false),
                    .redisBackupRetention(20),
                ],
                restart: true
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig
        )

        XCTAssertTrue(plan.restart)
        XCTAssertEqual(plan.logMessage, "runtime configuration updated restart=true")
        let expectedEffects: [ConfigureRuntimeEffect] = [
            .resizeVMDiskIfNeeded(64),
            .setInstalledProxyPort(18080),
            .createDirectory(URL(fileURLWithPath: "/data/vital-files"), withIntermediateDirectories: true),
            .setStartOnBoot(false),
            .setSystemSleepPrevention(false),
            .restrictSecretFile(harness.guestConfigURL),
            .restartRuntimeServices,
        ]
        XCTAssertEqual(plan.effects, expectedEffects)

        XCTAssertEqual(plan.vmConfig.configureCPUCount, 4)
        XCTAssertEqual(plan.vmConfig.configureMemoryMiB, 8192)
        XCTAssertEqual(plan.vmConfig.configureNetworkMode, .shared)
        XCTAssertNil(plan.vmConfig.configureBridgedInterface)
        XCTAssertEqual(plan.vmConfig.vitalFilesDirectory?.hostPath, "/data/vital-files")
        XCTAssertEqual(plan.vmConfig.configureAutoRecoveryEnabled, false)
        XCTAssertEqual(plan.vmConfig.configurePreventSystemSleep, false)

        XCTAssertEqual(plan.guestRuntimeConfig.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(plan.guestRuntimeConfig.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(plan.guestRuntimeConfig.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(plan.guestRuntimeConfig.publicPort, 443)
        XCTAssertEqual(plan.guestRuntimeConfig.adminPassword, "secret")
        XCTAssertEqual(plan.guestRuntimeConfig.vitalFilesDirectory, "/mnt/vital-files")
        XCTAssertEqual(plan.guestRuntimeConfig.redisBackupRetentionCount, 20)

        XCTAssertEqual(plan.guestRuntimeSettings.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(plan.guestRuntimeSettings.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(plan.guestRuntimeSettings.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(plan.guestRuntimeSettings.publicPort, 443)
        XCTAssertEqual(plan.guestRuntimeSettings.redisBackupRetentionCount, 20)
    }

    func testRejectsAdminPasswordFileBeforeWorkflowResolvesIt() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.useCase.plan(
            ConfigureRuntimeRequest(changes: [.adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password"))]),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig
        )) { error in
            XCTAssertEqual(
                error as? ConfigureRuntimeError,
                .invalidArgument("--admin-password-file must be resolved before planning path=/tmp/admin-password")
            )
        }
    }

    func testResolvesSecretFileContentIntoAdminPasswordChange() throws {
        let harness = Harness()

        let change = try harness.useCase.resolvedAdminPasswordChange(from: ConfigureRuntimeSecretFileInput(
            path: "/tmp/admin-password",
            contents: "secret"
        ))

        XCTAssertEqual(change, ConfigureRuntimeChange<ConfigureTestNetworkMode>.adminPassword("secret"))
    }

    func testRejectsInvalidSecretFileContentWithoutFallbackPassword() {
        let harness = Harness()

        for contents in ["", "line1\nline2"] {
            XCTAssertThrowsError(try harness.useCase.resolvedAdminPasswordChange(from: ConfigureRuntimeSecretFileInput(
                path: "/tmp/admin-password",
                contents: contents
            ))) { error in
                XCTAssertEqual(
                    error as? ConfigureRuntimeError,
                    .invalidArgument(
                        "--admin-password-file must contain a non-empty single-line password path=/tmp/admin-password"
                    )
                )
            }
        }
    }

    func testRejectsInvalidAdvertisedURL() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.useCase.plan(
            ConfigureRuntimeRequest(changes: [.vitalServerURL("vitaldb.tirosh.ai")]),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig
        )) { error in
            XCTAssertEqual(
                error as? ConfigureRuntimeError,
                .invalidArgument("--vitalserver-url must be an absolute http/https URL")
            )
        }
    }

    func testRejectsEmptyAdvertisedURL() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.useCase.plan(
            ConfigureRuntimeRequest(changes: [.remoteConsoleURL("")]),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig
        )) { error in
            XCTAssertEqual(
                error as? ConfigureRuntimeError,
                .invalidArgument("--remote-console-url must be an absolute http/https URL")
            )
        }
    }

    func testVitalServerHTTPURLWithoutExplicitPortUsesDefaultPublicPort() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(changes: [
                .publicPort(8080),
                .vitalServerURL("http://vitaldb.tirosh.ai/"),
            ]),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig
        )

        XCTAssertEqual(plan.guestRuntimeConfig.vitalServerURL, "http://vitaldb.tirosh.ai/")
        XCTAssertEqual(plan.guestRuntimeConfig.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(plan.guestRuntimeConfig.publicPort, 80)
    }

    func testRejectsBridgedModeWithoutInterface() {
        let harness = Harness()
        var vmConfig = harness.vmConfig
        vmConfig.configureBridgedInterface = nil

        XCTAssertThrowsError(try harness.useCase.plan(
            ConfigureRuntimeRequest(changes: [.network(.bridged)]),
            context: harness.context,
            currentVMConfig: vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig
        )) { error in
            XCTAssertEqual(
                error as? ConfigureRuntimeError,
                .invalidArgument("--bridged-interface is required when --network bridged")
            )
        }
    }

    final class Harness {
        let vmConfigURL = URL(fileURLWithPath: "/runtime/vm-config.json")
        let guestConfigURL = URL(fileURLWithPath: "/runtime/runtime-config.json")
        let guestSettingsURL = URL(fileURLWithPath: "/runtime/runtime-settings.json")
        let useCase = ConfigureRuntimeUseCase<ConfigureTestVMConfig>()

        lazy var context: ConfigureRuntimeContext<ConfigureTestNetworkMode> = ConfigureRuntimeContext(
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

struct ConfigureTestVMConfig: Codable, Equatable, ConfigureRuntimeMutableVMRuntimeConfiguration {
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

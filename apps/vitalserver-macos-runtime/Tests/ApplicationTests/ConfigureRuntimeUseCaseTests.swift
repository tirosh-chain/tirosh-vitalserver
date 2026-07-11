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
                    .backupRetention(20),
                ],
                restart: true
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )

        XCTAssertTrue(plan.restart)
        XCTAssertEqual(plan.restartRequirement, .vmRuntime)
        XCTAssertEqual(plan.logMessage, "runtime configuration updated restart=true restartRequirement=vmRuntime")
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
        XCTAssertEqual(plan.guestRuntimeSettings.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(plan.guestRuntimeSettings.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(plan.guestRuntimeSettings.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(plan.guestRuntimeSettings.publicPort, 443)
        XCTAssertEqual(plan.guestRuntimeSettings.backupRetentionCount, 20)
    }

    func testRestartPolicyDoesNotRestartForNonVMRuntimeChanges() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .proxyPort(18080),
                    .vitalServerURL("https://vitaldb.tirosh.ai/"),
                    .remoteConsoleURL("https://console.tirosh.ai/"),
                    .adminPassword("secret"),
                    .startOnBoot(false),
                    .autoRecovery(false),
                    .preventSystemSleep(false),
                    .backupRetention(20),
                ],
                restart: true
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )

        XCTAssertFalse(plan.restart)
        XCTAssertEqual(plan.restartRequirement, .none)
        XCTAssertFalse(plan.effects.contains(.restartRuntimeServices))
        XCTAssertEqual(plan.logMessage, "runtime configuration updated restart=false restartRequirement=none")
    }

    func testRestartPolicyRequiresGuestStackReconcileForRecorderIngressChange() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .recorderIngressSendDataReplayMaxMiBPerSecond(25),
                ],
                restart: true
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )

        XCTAssertTrue(plan.restart)
        XCTAssertEqual(plan.restartRequirement, .guestStack)
        XCTAssertTrue(plan.effects.contains(.reconcileGuestStackServices))
        XCTAssertFalse(plan.effects.contains(.restartRuntimeServices))
        XCTAssertEqual(
            plan.logMessage,
            "runtime configuration updated restart=true restartRequirement=guestStack"
        )
        XCTAssertEqual(plan.guestRuntimeSettings.recorderIngressSendDataReplayMaxMiBPerSecond, 25)
    }

    func testRestartPolicyRequiresVMRuntimeRestartForVitalFilesDirectoryChange() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .vitalFilesDirectory(URL(fileURLWithPath: "/data/vital-files")),
                ],
                restart: false
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )

        XCTAssertFalse(plan.restart)
        XCTAssertEqual(plan.restartRequirement, .vmRuntime)
        XCTAssertFalse(plan.effects.contains(.restartRuntimeServices))
    }

    func testRestartPolicyUsesActualConfigDiffInsteadOfSubmittedFields() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .cpu(harness.vmConfig.configureCPUCount),
                    .memoryGiB(harness.vmConfig.configureMemoryMiB / 1024),
                    .network(harness.vmConfig.configureNetworkMode),
                    .bridgedInterface(harness.vmConfig.configureBridgedInterface ?? "en0"),
                    .vitalFilesDirectory(URL(fileURLWithPath: "/old-vital")),
                ],
                restart: true
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )

        XCTAssertFalse(plan.restart)
        XCTAssertEqual(plan.restartRequirement, .none)
    }

    func testRestartPolicyRequiresVMRuntimeRestartForDiskIncrease() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .diskGiB(harness.currentDiskGiB + harness.context.diskStepGiB),
                ],
                restart: false
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )

        XCTAssertFalse(plan.restart)
        XCTAssertEqual(plan.restartRequirement, .vmRuntime)
        XCTAssertFalse(plan.effects.contains(.restartRuntimeServices))
    }

    func testRestartPolicyDoesNotRequireRestartForSubmittedCurrentDiskSize() throws {
        let harness = Harness()

        let plan = try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .diskGiB(harness.currentDiskGiB),
                ],
                restart: true
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )

        XCTAssertFalse(plan.restart)
        XCTAssertEqual(plan.restartRequirement, .none)
        XCTAssertFalse(plan.effects.contains(.restartRuntimeServices))
    }

    func testRejectsDiskShrinkAgainstExplicitCurrentDiskSize() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .diskGiB(harness.currentDiskGiB - harness.context.diskStepGiB),
                ]
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )) { error in
            XCTAssertEqual(
                error as? ConfigureRuntimeError,
                .invalidArgument("--disk-gib can only increase the VM disk; current disk is 32 GiB")
            )
        }
    }

    func testRejectsDuplicateBackupScheduleTimes() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.useCase.plan(
            ConfigureRuntimeRequest(
                changes: [
                    .backupScheduleTimes(["03:15", "03:15"]),
                ]
            ),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
        )) { error in
            XCTAssertEqual(
                error as? ConfigureRuntimeError,
                .invalidArgument("--backup-schedule-times must be unique comma-separated HH:mm values")
            )
        }
    }

    func testEffectExecutionPlanKeepsPreAndPostWriteOrderingOutOfWorkflow() {
        let harness = Harness()
        let effects: [ConfigureRuntimeEffect] = [
            .resizeVMDiskIfNeeded(64),
            .restrictSecretFile(harness.guestConfigURL),
            .setInstalledProxyPort(18080),
            .restartRuntimeServices,
            .createDirectory(URL(fileURLWithPath: "/data/vital-files"), withIntermediateDirectories: true),
            .setStartOnBoot(false),
            .setSystemSleepPrevention(false),
        ]

        let plan = harness.useCase.effectExecutionPlan(effects)

        XCTAssertEqual(plan.preWriteEffects, [
            .resizeVMDiskIfNeeded(64),
            .setInstalledProxyPort(18080),
            .createDirectory(URL(fileURLWithPath: "/data/vital-files"), withIntermediateDirectories: true),
            .setStartOnBoot(false),
            .setSystemSleepPrevention(false),
        ])
        XCTAssertEqual(plan.postWriteEffects, [
            .restrictSecretFile(harness.guestConfigURL),
            .restartRuntimeServices,
        ])
    }

    func testRejectsAdminPasswordFileBeforeWorkflowResolvesIt() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.useCase.plan(
            ConfigureRuntimeRequest(changes: [.adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password"))]),
            context: harness.context,
            currentVMConfig: harness.vmConfig,
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
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
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
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
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
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
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
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
            currentGuestRuntimeConfig: harness.guestConfig,
            currentGuestRuntimeSettings: harness.guestSettings,
            currentVMDiskSizeGiB: harness.currentDiskGiB
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
        let currentDiskGiB = 32

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
            maximumBackupRetentionCount: 30,
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
            configurePreventSystemSleep: true,
            vitalFilesDirectory: ConfigureTestSharedDirectory(
                hostPath: "/old-vital",
                tag: "vital-files",
                guestMountPath: "/mnt/vital-files",
                readOnly: false
            )
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
            redisUiPort: 18081,
            swaggerUiPort: 18082
        )
        var guestSettings = GuestRuntimeSettingsDocument(
            vitalServerURL: "",
            remoteConsoleURL: "",
            publicHost: "",
            publicPort: 80,
            automaticBackupEnabled: true,
            backupScheduleTimes: ["03:15"],
            backupRetentionCount: 30
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

    var configureVitalFilesDirectoryHostPath: String? {
        vitalFilesDirectory?.hostPath
    }

    mutating func setConfigureVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        vitalFilesDirectory = ConfigureTestSharedDirectory(
            hostPath: directory.hostPath,
            tag: directory.tag,
            guestMountPath: directory.guestMountPath,
            readOnly: directory.readOnly
        )
    }
}

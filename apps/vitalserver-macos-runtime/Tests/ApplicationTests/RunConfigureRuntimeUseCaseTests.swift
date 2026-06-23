import Application
import Contracts
import Foundation
import XCTest
import Errors

final class RunConfigureRuntimeUseCaseTests: XCTestCase {
    func testConfigureReadsExplicitStateResolvesSecretAndExecutesWritesAndEffects() throws {
        let harness = Harness()

        let result = try harness.configure(
            ConfigureRuntimeRequest(
                changes: [
                    .diskGiB(64),
                    .proxyPort(18080),
                    .vitalFilesDirectory(URL(fileURLWithPath: "/data/vital-files")),
                    .adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password")),
                    .startOnBoot(false),
                    .recorderIngressSendDataMode(.mirrorSpool),
                    .recorderIngressSendDataReplayBatchSize(8),
                    .recorderIngressSendDataReplayRateLimitPerSecond(12),
                    .preventSystemSleep(false),
                ],
                restart: true
            ),
            context: harness.context
        )

        XCTAssertTrue(result.restart)
        XCTAssertEqual(result.restartRequirement, .vmRuntime)
        XCTAssertEqual(harness.readSecretFiles, [URL(fileURLWithPath: "/tmp/admin-password")])
        XCTAssertEqual(harness.preWriteEffects, [
            "resize:64",
            "proxy:18080",
            "mkdir:/data/vital-files:true",
            "start-on-boot:false",
            "sleep:false",
        ])
        XCTAssertEqual(harness.postWriteEffects, [
            "restrict:/runtime/runtime-config.json",
            "restart",
        ])
        XCTAssertEqual(harness.logs, ["runtime configuration updated restart=true restartRequirement=vmRuntime"])
        XCTAssertEqual(harness.writes.map(\.url), [
            harness.vmConfigURL,
            harness.guestConfigURL,
            harness.guestSettingsURL,
        ])

        let guestConfig = try JSONDecoder().decode(
            GuestRuntimeConfigDocument.self,
            from: XCTUnwrap(harness.writes.first { $0.url == harness.guestConfigURL }?.data)
        )
        XCTAssertEqual(guestConfig.adminPassword, "secret")
        XCTAssertEqual(guestConfig.vitalFilesDirectory, "/mnt/vital-files")
        let guestSettings = try JSONDecoder().decode(
            GuestRuntimeSettingsDocument.self,
            from: XCTUnwrap(harness.writes.first { $0.url == harness.guestSettingsURL }?.data)
        )
        XCTAssertEqual(guestSettings.recorderIngressSendDataMode, .mirrorSpool)
        XCTAssertEqual(guestSettings.recorderIngressSendDataReplayBatchSize, 8)
        XCTAssertEqual(guestSettings.recorderIngressSendDataReplayRateLimitPerSecond, 12)
    }

    func testInvalidSecretFileContentFailsBeforeWrites() {
        let harness = Harness()
        harness.secretFileContents = ""

        XCTAssertThrowsError(try harness.configure(
            ConfigureRuntimeRequest(changes: [.adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password"))]),
            context: harness.context
        )) { error in
            XCTAssertEqual(
                error as? ConfigureRuntimeError,
                .invalidArgument(
                    "--admin-password-file must contain a non-empty single-line password path=/tmp/admin-password"
                )
            )
        }
        XCTAssertTrue(harness.writes.isEmpty)
        XCTAssertTrue(harness.preWriteEffects.isEmpty)
        XCTAssertTrue(harness.postWriteEffects.isEmpty)
    }

    func testSecretFileReadFailurePropagatesBeforeWrites() {
        let harness = Harness()
        harness.secretFileError = RuntimeConfigureWorkflowTestError.secretReadFailed

        XCTAssertThrowsError(try harness.configure(
            ConfigureRuntimeRequest(changes: [.adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password"))]),
            context: harness.context
        )) { error in
            XCTAssertEqual(error as? RuntimeConfigureWorkflowTestError, .secretReadFailed)
        }
        XCTAssertEqual(harness.readSecretFiles, [URL(fileURLWithPath: "/tmp/admin-password")])
        XCTAssertTrue(harness.writes.isEmpty)
        XCTAssertTrue(harness.preWriteEffects.isEmpty)
        XCTAssertTrue(harness.postWriteEffects.isEmpty)
    }

    final class Harness {
        let vmConfigURL = URL(fileURLWithPath: "/runtime/vm-config.json")
        let guestConfigURL = URL(fileURLWithPath: "/runtime/runtime-config.json")
        let guestSettingsURL = URL(fileURLWithPath: "/runtime/runtime-settings.json")
        var secretFileContents = "secret"
        var secretFileError: RuntimeConfigureWorkflowTestError?
        var readSecretFiles: [URL] = []
        var preWriteEffects: [String] = []
        var postWriteEffects: [String] = []
        var logs: [String] = []
        var writes: [(data: Data, url: URL)] = []
        var currentDiskGiB = 32

        lazy var context: ConfigureRuntimeContext<ConfigureWorkflowTestNetworkMode> = ConfigureRuntimeContext(
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

        func configure(
            _ request: ConfigureRuntimeRequest<ConfigureWorkflowTestNetworkMode>,
            context: ConfigureRuntimeContext<ConfigureWorkflowTestNetworkMode>
        ) throws -> ConfigureRuntimeResult {
            try RunConfigureRuntimeUseCase<ConfigureWorkflowTestVMConfig>().configure(
                request,
                context: context,
                operations: operations
            )
        }

        lazy var operations = ConfigureRuntimeOperations(
            readers: ConfigureRuntimeStateReaders(
                loadVMConfig: { _ in self.vmConfig },
                loadGuestRuntimeConfig: { _ in self.guestConfig },
                loadGuestRuntimeSettings: { _ in self.guestSettings },
                loadVMDiskSizeGiB: { self.currentDiskGiB }
            ),
            writer: ConfigureRuntimeDocumentWriter(
                encodeVMConfig: { try JSONEncoder().encode($0) },
                encodeGuestRuntimeConfig: { try JSONEncoder().encode($0) },
                encodeGuestRuntimeSettings: { try JSONEncoder().encode($0) },
                writeData: { data, url, _ in
                    self.writes.append((data: data, url: url))
                }
            ),
            effects: ConfigureRuntimeEffects(
                resolveSecretFileChanges: { request in
                    try self.resolveSecretFileChanges(in: request)
                },
                executeEffects: { effects in
                    try self.executeEffects(effects)
                },
                ensureRuntimeDefaults: { _ in },
                log: { message in
                    self.logs.append(message)
                }
            )
        )

        func resolveSecretFileChanges(
            in request: ConfigureRuntimeRequest<ConfigureWorkflowTestNetworkMode>
        ) throws -> ConfigureRuntimeRequest<ConfigureWorkflowTestNetworkMode> {
            let useCase = ConfigureRuntimeUseCase<ConfigureWorkflowTestVMConfig>()
            let changes = try request.changes.map { change in
                switch change {
                case .adminPasswordFile(let url):
                    readSecretFiles.append(url)
                    if let secretFileError {
                        throw secretFileError
                    }
                    return try useCase.resolvedAdminPasswordChange(from: ConfigureRuntimeSecretFileInput(
                        path: url.path,
                        contents: secretFileContents
                    ))
                default:
                    return change
                }
            }
            return ConfigureRuntimeRequest(changes: changes, restart: request.restart)
        }

        func executeEffects(_ effects: [ConfigureRuntimeEffect]) throws {
            for effect in effects {
                switch effect {
                case .createDirectory(let url, let withIntermediateDirectories):
                    preWriteEffects.append("mkdir:\(url.path):\(withIntermediateDirectories)")
                case .resizeVMDiskIfNeeded(let diskGiB):
                    preWriteEffects.append("resize:\(diskGiB)")
                case .setInstalledProxyPort(let port):
                    preWriteEffects.append("proxy:\(port)")
                case .restrictSecretFile(let url):
                    postWriteEffects.append("restrict:\(url.path)")
                case .setStartOnBoot(let enabled):
                    preWriteEffects.append("start-on-boot:\(enabled)")
                case .setSystemSleepPrevention(let enabled):
                    preWriteEffects.append("sleep:\(enabled)")
                case .setAutomaticBackupSchedule(let enabled, let scheduleTimes):
                    preWriteEffects.append("automatic-backup:\(enabled):\(scheduleTimes.joined(separator: ","))")
                case .setLogArchiveRetentionDays(let days):
                    postWriteEffects.append("log-archive-retention-days:\(days)")
                case .setLogArchiveMaximumGiB(let gib):
                    postWriteEffects.append("log-archive-maximum-gib:\(gib)")
                case .writeRedisRelayConfiguration(let settings):
                    postWriteEffects.append("redis-relay:\(settings.enabled):\(settings.target.url)")
                case .reconcileGuestComposeServices:
                    postWriteEffects.append("reconcile-compose")
                case .restartRuntimeServices:
                    postWriteEffects.append("restart")
                }
            }
        }

        var vmConfig = ConfigureWorkflowTestVMConfig(
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
            redisUiPort: 18081,
            swaggerUiPort: 18082,
            testkitEnabled: false
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

enum RuntimeConfigureWorkflowTestError: Error, Equatable {
    case secretReadFailed
}

enum ConfigureWorkflowTestNetworkMode: String, Codable, Equatable {
    case shared
    case bridged
}

struct ConfigureWorkflowTestSharedDirectory: Codable, Equatable {
    var hostPath: String
    var tag: String
    var guestMountPath: String
    var readOnly: Bool
}

struct ConfigureWorkflowTestVMConfig: Codable, Equatable, ConfigureRuntimeMutableVMRuntimeConfiguration {
    var configureCPUCount: Int
    var configureMemoryMiB: UInt64
    var configureNetworkMode: ConfigureWorkflowTestNetworkMode
    var configureBridgedInterface: String?
    var configureAutoRecoveryEnabled: Bool?
    var configurePreventSystemSleep: Bool?
    var vitalFilesDirectory: ConfigureWorkflowTestSharedDirectory?

    var configureVitalFilesDirectoryHostPath: String? {
        vitalFilesDirectory?.hostPath
    }

    mutating func setConfigureVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        vitalFilesDirectory = ConfigureWorkflowTestSharedDirectory(
            hostPath: directory.hostPath,
            tag: directory.tag,
            guestMountPath: directory.guestMountPath,
            readOnly: directory.readOnly
        )
    }
}

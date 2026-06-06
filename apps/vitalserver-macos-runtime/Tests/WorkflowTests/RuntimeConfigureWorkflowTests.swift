import Application
import Contracts
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeConfigureWorkflowTests: XCTestCase {
    func testConfigureReadsExplicitStateResolvesSecretAndExecutesWritesAndEffects() throws {
        let harness = Harness()

        let result = try harness.workflow.configure(
            ConfigureRuntimeRequest(
                changes: [
                    .diskGiB(64),
                    .proxyPort(18080),
                    .vitalFilesDirectory(URL(fileURLWithPath: "/data/vital-files")),
                    .adminPasswordFile(URL(fileURLWithPath: "/tmp/admin-password")),
                    .startOnBoot(false),
                    .preventSystemSleep(false),
                ],
                restart: true
            ),
            context: harness.context
        )

        XCTAssertTrue(result.restart)
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
        XCTAssertEqual(harness.logs, ["runtime configuration updated restart=true"])
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
    }

    func testInvalidSecretFileContentFailsBeforeWrites() {
        let harness = Harness()
        harness.secretFileContents = ""

        XCTAssertThrowsError(try harness.workflow.configure(
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

        XCTAssertThrowsError(try harness.workflow.configure(
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
            maximumRedisBackupRetentionCount: 30,
            defaultPublicPort: 80,
            sharedNetworkMode: .shared,
            bridgedNetworkMode: .bridged,
            vitalFilesDirectoryTag: "vital-files",
            vitalFilesDirectoryGuestMountPath: "/mnt/vital-files"
        )

        lazy var workflow = RuntimeConfigureWorkflow(
            readers: RuntimeConfigureStateReaders(
                loadVMConfig: { _ in self.vmConfig },
                loadGuestRuntimeConfig: { _ in self.guestConfig }
            ),
            writer: RuntimeConfigureDocumentWriter(
                encodeVMConfig: { try JSONEncoder().encode($0) },
                encodeGuestRuntimeConfig: { try JSONEncoder().encode($0) },
                encodeGuestRuntimeSettings: { try JSONEncoder().encode($0) },
                writeData: { data, url, _ in
                    self.writes.append((data: data, url: url))
                }
            ),
            effects: RuntimeConfigureEffects(
                createDirectory: { url, withIntermediateDirectories in
                    self.preWriteEffects.append("mkdir:\(url.path):\(withIntermediateDirectories)")
                },
                resizeVMDiskIfNeeded: { diskGiB in
                    self.preWriteEffects.append("resize:\(diskGiB)")
                },
                setInstalledProxyPort: { port in
                    self.preWriteEffects.append("proxy:\(port)")
                },
                readSecretFile: { url in
                    self.readSecretFiles.append(url)
                    if let secretFileError = self.secretFileError {
                        throw secretFileError
                    }
                    return self.secretFileContents
                },
                restrictSecretFile: { url in
                    self.postWriteEffects.append("restrict:\(url.path)")
                },
                setStartOnBoot: { enabled in
                    self.preWriteEffects.append("start-on-boot:\(enabled)")
                },
                setSystemSleepPrevention: { enabled in
                    self.preWriteEffects.append("sleep:\(enabled)")
                },
                restartRuntimeServices: {
                    self.postWriteEffects.append("restart")
                },
                ensureRuntimeDefaults: { _ in },
                log: { message in
                    self.logs.append(message)
                }
            )
        )

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
            redisBackupRetentionCount: 30,
            redisUiPort: 18081,
            swaggerUiPort: 18082,
            testkitEnabled: false
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

    mutating func setConfigureVitalFilesDirectory(_ directory: RuntimeSharedDirectoryConfiguration) {
        vitalFilesDirectory = ConfigureWorkflowTestSharedDirectory(
            hostPath: directory.hostPath,
            tag: directory.tag,
            guestMountPath: directory.guestMountPath,
            readOnly: directory.readOnly
        )
    }
}

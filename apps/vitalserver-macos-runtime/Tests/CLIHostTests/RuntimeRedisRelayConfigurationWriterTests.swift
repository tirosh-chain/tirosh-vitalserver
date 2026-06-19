import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl
@testable import CLIHost
import XCTest

final class RuntimeRedisRelayConfigurationWriterTests: XCTestCase {
    func testEnsureInstallConfigurationCreatesFreshDisabledRelayContract() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let writer = RuntimeRedisRelayConfigurationWriter(
            installedPaths: paths,
            fileStore: fileStore
        )

        try writer.ensureInstallConfiguration()

        XCTAssertTrue(fileStore.directories.contains(paths.redisRelayConfigDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.redisRelaySecretsDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.redisRelayStatusDirectory))

        let toml = String(
            data: try XCTUnwrap(fileStore.files[paths.redisRelayConfig]),
            encoding: .utf8
        )
        XCTAssertTrue(toml?.contains("enabled = false") == true)
        XCTAssertTrue(toml?.contains("scope = \"vital_reconstruction\"") == true)
        XCTAssertTrue(toml?.contains("url = \"redis://127.0.0.1:16381/0\"") == true)

        let settingsData = try XCTUnwrap(fileStore.files[paths.runtimeControlSettings])
        let settings = try JSONDecoder().decode(RuntimeControlSettingsDocument.self, from: settingsData)
        XCTAssertFalse(settings.redisRelay.enabled)
    }

    func testEnsureInstallConfigurationUsesStoredRelaySettingsWhenConfigIsMissing() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        fileStore.files[paths.runtimeControlSettings] = try JSONEncoder().encode(
            RuntimeControlSettingsDocument(
                redisRelay: RuntimeRedisRelaySettings(
                    enabled: true,
                    target: RuntimeRedisRelayTarget(
                        url: "redis://redis-hub.internal:6380/2",
                        username: "relay",
                        passwordConfigured: true,
                        tls: true
                    ),
                    scope: .vitalReconstruction,
                    includeRecorderNetworkContext: true,
                    intervalSeconds: 0.5,
                    scanCount: 500
                )
            )
        )
        fileStore.files[paths.redisRelayTargetPassword] = Data("secret-password".utf8)
        let writer = RuntimeRedisRelayConfigurationWriter(
            installedPaths: paths,
            fileStore: fileStore
        )

        try writer.ensureInstallConfiguration()

        let toml = String(
            data: try XCTUnwrap(fileStore.files[paths.redisRelayConfig]),
            encoding: .utf8
        )
        XCTAssertTrue(toml?.contains("enabled = true") == true)
        XCTAssertTrue(toml?.contains("include_recorder_network_context = true") == true)
        XCTAssertTrue(toml?.contains("interval_seconds = 0.5") == true)
        XCTAssertTrue(toml?.contains("scan_count = 500") == true)
        XCTAssertTrue(toml?.contains("url = \"rediss://relay@redis-hub.internal:6380/2\"") == true)
        XCTAssertTrue(toml?.contains("password_file = \"/run/tirosh/secrets/redis-relay-target-password\"") == true)
    }

    func testEnsureInstallConfigurationFailsWhenStoredRelayPasswordSecretIsMissing() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        fileStore.files[paths.runtimeControlSettings] = try JSONEncoder().encode(
            RuntimeControlSettingsDocument(
                redisRelay: RuntimeRedisRelaySettings(
                    enabled: true,
                    target: RuntimeRedisRelayTarget(passwordConfigured: true)
                )
            )
        )
        let writer = RuntimeRedisRelayConfigurationWriter(
            installedPaths: paths,
            fileStore: fileStore
        )

        XCTAssertThrowsError(try writer.ensureInstallConfiguration()) { error in
            XCTAssertTrue(
                String(describing: error).contains("Redis relay password is configured but secret file is missing"),
                "unexpected error: \(error)"
            )
        }
    }

    func testEnsureInstallConfigurationPreservesExistingRelayConfig() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        fileStore.files[paths.redisRelayConfig] = Data("existing-config\n".utf8)
        let writer = RuntimeRedisRelayConfigurationWriter(
            installedPaths: paths,
            fileStore: fileStore
        )

        try writer.ensureInstallConfiguration()

        XCTAssertEqual(
            String(data: try XCTUnwrap(fileStore.files[paths.redisRelayConfig]), encoding: .utf8),
            "existing-config\n"
        )
    }
}

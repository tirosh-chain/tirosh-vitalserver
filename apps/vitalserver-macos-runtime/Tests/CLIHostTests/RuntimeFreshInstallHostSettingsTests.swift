import Application
import Bootstrap
import Contracts
import Domain
import Foundation
import InboundAdapters
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeFreshInstallHostSettingsTests: XCTestCase {
    func testPackageInstallContractRoundTripsExplicitFreshMode() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-package-install-contract-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let lifecycle = makeLifecycle(productRoot: productRoot)
        let contractURL = productRoot.appendingPathComponent("package-install-contract.json")
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)

        try lifecycle.writePackageInstallContract(mode: .fresh, to: contractURL)

        XCTAssertEqual(
            try lifecycle.loadPackageInstallContract(from: contractURL),
            RuntimePackageInstallContract(
                packageIdentifier: Constants.Product.identifier,
                mode: .fresh
            )
        )
    }

    func testPackageInstallContractRejectsUnsupportedSchema() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-package-install-contract-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let lifecycle = makeLifecycle(productRoot: productRoot)
        let contractURL = productRoot.appendingPathComponent("package-install-contract.json")
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(
            RuntimePackageInstallContract(
                schemaVersion: RuntimePackageInstallContract.currentSchemaVersion + 1,
                packageIdentifier: Constants.Product.identifier,
                mode: .fresh
            )
        ).write(to: contractURL)

        XCTAssertThrowsError(try lifecycle.loadPackageInstallContract(from: contractURL)) { error in
            XCTAssertTrue(String(describing: error).contains("schema is unsupported"))
        }
    }

    func testPackageInstallContractRejectsDifferentPackageIdentifier() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-package-install-contract-identifier-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let lifecycle = makeLifecycle(productRoot: productRoot)
        let contractURL = productRoot.appendingPathComponent("package-install-contract.json")
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(
            RuntimePackageInstallContract(
                packageIdentifier: "example.invalid.package",
                mode: .fresh
            )
        ).write(to: contractURL)

        XCTAssertThrowsError(try lifecycle.loadPackageInstallContract(from: contractURL)) { error in
            XCTAssertTrue(String(describing: error).contains("identifier mismatch"))
        }
    }

    func testFreshInstallInitializesSQLiteBeforeMaterializingBootDocuments() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-fresh-install-host-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            clock: RuntimeFreshInstallFixedClock(),
            commandRunner: RuntimeFreshInstallCommandRunner()
        )
        let settings = RuntimeInstallSettings(
            vitalFilesDirectory: installedPaths.vitalFilesDirectory.path
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.vmConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.guestRuntimeConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.guestRuntimeSettings.path))

        try lifecycle.initializeHostStateStore()

        XCTAssertTrue(FileManager.default.fileExists(atPath: installedPaths.runtimeStateDatabase.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.vmConfig.path))
        guard case .missing = lifecycle.runtimeHostSettingsRepository().loadHostSettings() else {
            return XCTFail("state store initialization must not infer Host settings from files")
        }

        try lifecycle.runtimeInstallDirectoryPreparer().prepare(settings: settings)
        try lifecycle.prepareHostSettings(settings)

        let desired = try loadedSettings(lifecycle)
        XCTAssertEqual(desired.revision, 1)
        XCTAssertNil(desired.materializedRevision)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.vmConfig.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.guestRuntimeConfig.path))

        try lifecycle.configureDeployEnvironment(settings)

        XCTAssertFalse(FileManager.default.fileExists(atPath: installedPaths.vmConfig.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedPaths.guestRuntimeConfig.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedPaths.guestRuntimeSettings.path))
        XCTAssertEqual(
            try JSONDecoder().decode(
                RuntimeControlSettingsDocument.self,
                from: Data(contentsOf: installedPaths.runtimeControlSettings)
            ),
            RuntimeControlSettingsDocument()
        )

        try lifecycle.configureInstalledVMRuntime(settings)

        let materialized = try loadedSettings(lifecycle)
        XCTAssertEqual(materialized.materializedRevision, 1)
        XCTAssertEqual(
            materialized.payload.vmConfigJSON,
            try Data(contentsOf: installedPaths.vmConfig)
        )
        XCTAssertEqual(
            materialized.payload.guestRuntimeConfigJSON,
            try Data(contentsOf: installedPaths.guestRuntimeConfig)
        )
        XCTAssertEqual(
            materialized.payload.guestRuntimeSettingsJSON,
            try Data(contentsOf: installedPaths.guestRuntimeSettings)
        )
    }

    func testPackageProvisionPreservesValidRuntimeControlSettings() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-control-settings-preserve-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = makeLifecycle(productRoot: productRoot)
        let expected = RuntimeControlSettingsDocument(
            logArchiveRetentionDays: 31,
            logArchiveMaximumGiB: 7,
            runtimeControlPort: 19_321
        )
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let original = try JSONEncoder().encode(expected)
        try original.write(to: installedPaths.runtimeControlSettings)

        try lifecycle.prepareRuntimeControlSettings()

        XCTAssertEqual(try Data(contentsOf: installedPaths.runtimeControlSettings), original)
    }

    func testPackageProvisionRejectsInvalidRuntimeControlSettings() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-control-settings-invalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = makeLifecycle(productRoot: productRoot)
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: installedPaths.runtimeControlSettings)

        XCTAssertThrowsError(try lifecycle.prepareRuntimeControlSettings()) { error in
            XCTAssertTrue(String(describing: error).contains("validation failed"))
        }
    }

    func testPackageProvisionReplacesCloudInitSeedToActivateGuestBootstrap() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-package-seed-refresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = makeLifecycle(productRoot: productRoot)
        try FileManager.default.createDirectory(
            at: installedPaths.runtimeDirectory,
            withIntermediateDirectories: true
        )
        try Data("previous-seed".utf8).write(
            to: installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.cloudInit)
        )

        try lifecycle.createCloudInitSeed(RuntimeInstallSettings(
            vitalFilesDirectory: installedPaths.vitalFilesDirectory.path
        ))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: installedPaths.runtimeDirectory
                .appendingPathComponent(Constants.BootAssets.cloudInit).path
        ))
        let metadata = try String(
            contentsOf: installedPaths.runtimeDirectory
                .appendingPathComponent("cloud-init-seed/meta-data"),
            encoding: .utf8
        )
        XCTAssertTrue(metadata.contains("instance-id:"))
    }

    func testPackageProvisionImportsCompleteLegacyMaterializedSettingsAndLoadsPreservedValues() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-legacy-host-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            clock: RuntimeFreshInstallFixedClock(),
            commandRunner: RuntimeFreshInstallCommandRunner()
        )
        var legacySettings = RuntimeInstallSettings(
            vitalFilesDirectory: productRoot.appendingPathComponent("vital-files").path
        )
        legacySettings.cpuCount = 7
        legacySettings.memoryGiB = 12
        legacySettings.proxyPort = 8080
        legacySettings.publicPort = 8080
        legacySettings.vitalServerURL = "http://127.0.0.1:8080/"
        let payload = try lifecycle.freshInstallHostSettingsPayload(legacySettings)

        try FileManager.default.createDirectory(
            at: installedPaths.runtimeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: installedPaths.deployDirectory,
            withIntermediateDirectories: true
        )
        try payload.vmConfigJSON.write(to: installedPaths.vmConfig)
        try payload.guestRuntimeConfigJSON.write(to: installedPaths.guestRuntimeConfig)
        try payload.guestRuntimeSettingsJSON.write(to: installedPaths.guestRuntimeSettings)
        FileManager.default.createFile(atPath: installedPaths.vmDisk.path, contents: Data())
        let disk = try FileHandle(forWritingTo: installedPaths.vmDisk)
        try disk.truncate(atOffset: UInt64(48) * 1_073_741_824)
        try disk.close()

        try lifecycle.initializeHostStateStore()
        try lifecycle.migrateLegacyHostSettingsIfNeeded()
        let settings = try lifecycle.loadPackageProvisionSettings()

        let imported = try loadedSettings(lifecycle)
        XCTAssertEqual(imported.materializedRevision, 1)
        XCTAssertEqual(settings.cpuCount, 7)
        XCTAssertEqual(settings.memoryGiB, 12)
        XCTAssertEqual(settings.diskGiB, 48)
        XCTAssertEqual(settings.proxyPort, 8080)
        XCTAssertEqual(settings.vitalServerURL, "http://127.0.0.1:8080/")
        XCTAssertTrue(settings.startOnBoot)
        XCTAssertTrue(settings.startAfterInstall)
    }

    func testPackageProvisionRejectsPartialLegacyMaterializedSettings() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-partial-legacy-host-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            clock: RuntimeFreshInstallFixedClock(),
            commandRunner: RuntimeFreshInstallCommandRunner()
        )
        try FileManager.default.createDirectory(
            at: installedPaths.runtimeDirectory,
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: installedPaths.vmConfig)

        try lifecycle.initializeHostStateStore()

        XCTAssertThrowsError(try lifecycle.migrateLegacyHostSettingsIfNeeded()) { error in
            XCTAssertTrue(String(describing: error).contains("incomplete materialized state"))
        }
        guard case .missing = lifecycle.runtimeHostSettingsRepository().loadHostSettings() else {
            return XCTFail("partial legacy settings must not create Host settings state")
        }
    }

    func testPackageReinstallRejectsMissingSQLiteAndMissingLegacySettings() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-missing-reinstall-host-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: productRoot) }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            clock: RuntimeFreshInstallFixedClock(),
            commandRunner: RuntimeFreshInstallCommandRunner()
        )

        try lifecycle.initializeHostStateStore()
        try lifecycle.migrateLegacyHostSettingsIfNeeded()

        XCTAssertThrowsError(try lifecycle.requirePackageReinstallSettings()) { error in
            XCTAssertTrue(String(describing: error).contains("Host settings are missing"))
        }
    }

    private func loadedSettings(
        _ lifecycle: RuntimeLifecycle
    ) throws -> RuntimeHostSettingsRecord {
        switch lifecycle.runtimeHostSettingsRepository().loadHostSettings() {
        case .loaded(let record):
            return record
        case .missing:
            throw RuntimeFreshInstallHostSettingsTestError.settingsMissing
        case .failed(let reason):
            throw RuntimeFreshInstallHostSettingsTestError.settingsReadFailed(reason)
        }
    }

    private func makeLifecycle(productRoot: URL) -> RuntimeLifecycle {
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        return RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            clock: RuntimeFreshInstallFixedClock(),
            commandRunner: RuntimeFreshInstallCommandRunner()
        )
    }
}

private struct RuntimeFreshInstallFixedClock: RuntimeClock {
    let now = ISO8601DateFormatter().date(from: "2026-07-14T13:00:00Z")!
}

private struct RuntimeFreshInstallCommandRunner: RuntimeCommandRunner {
    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func runWritingOutput(
        _ executable: String,
        arguments: [String],
        output: URL
    ) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}

private enum RuntimeFreshInstallHostSettingsTestError: Error {
    case settingsMissing
    case settingsReadFailed(String)
}

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

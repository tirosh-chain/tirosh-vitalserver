import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeInstallCompositionSQLiteStateTests: XCTestCase {
    func testFreshPackageProvisionInitializesHostStateWithoutLegacyMigration() throws {
        let events = RuntimeInstallCompositionEventRecorder()
        let composition = makeProvisionComposition(events: events)

        try composition.installProvision()

        XCTAssertTrue(events.values.contains("initialize-state-store"))
        XCTAssertFalse(events.values.contains("migrate-legacy-settings"))
        XCTAssertTrue(events.values.contains("prepare-host-settings"))
    }

    func testFullInstallCapturesPreflightBeforePreparingSQLiteAndPersistsTerminalState() throws {
        let fileStore = RuntimeFileStoreSpy()
        let stateRepository = RuntimeWorkflowOperationStateRepositorySpy()
        var events: [String] = []
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let composition = RuntimeInstallComposition(
            context: RuntimeInstallCompositionContext(
                paths: LauncherPaths(
                    home: installedPaths.runtimeHome,
                    installed: installedPaths,
                    config: installedPaths.vmConfig,
                    pidFile: installedPaths.pidFile
                ),
                installedPaths: installedPaths
            ),
            operations: RuntimeInstallCompositionOperations(
                fileStore: fileStore,
                now: { Date(timeIntervalSince1970: 1_789_433_600) },
                loadInstallSettings: { "settings" },
                freshInstallPreflight: {
                    events.append("preflight")
                    return Self.preflight()
                },
                installProvisionPayload: { Self.provisionPayload() },
                writeRuntimeStatus: { _, _, _ in },
                writeRuntimeProgress: { _ in },
                prepareInstallDirectories: { _ in },
                rotateRuntimeLogs: {},
                configureDeployEnvironment: { _ in },
                prepareInstalledExecutables: {},
                provisionVMDisk: { _ in },
                configureInstalledVMRuntime: { _ in },
                createCloudInitSeed: { _ in },
                writeInstalledRuntimeVersion: {},
                configureInstalledPermissions: { _ in },
                startInstalledServices: { _ in },
                applyStartOnBootPolicy: { _ in },
                waitInstallRuntimeHealth: { _ in },
                cleanupInstallSettings: {},
                log: { _ in },
                initializeHostStateStore: {
                    events.append("initialize-state-store")
                },
                prepareHostSettings: { _ in
                    events.append("prepare-host-settings")
                },
                workflowOperationStateRepository: stateRepository,
                operationID: { "install-operation-1" },
                installationID: { "installation-1" },
                settleInstalledProductRelease: {
                    operationID,
                    installationID in
                    events.append(
                        "settle-release:\(operationID):\(installationID)"
                    )
                }
            )
        )

        try composition.install()

        XCTAssertEqual(Array(events.prefix(2)), ["preflight", "initialize-state-store"])
        XCTAssertEqual(events.filter { $0 == "initialize-state-store" }.count, 1)
        XCTAssertEqual(events.filter { $0 == "prepare-host-settings" }.count, 1)
        XCTAssertTrue(
            events.contains(
                "settle-release:install-operation-1:installation-1"
            )
        )
        let state = try XCTUnwrap(stateRepository.states["install-operation-1"])
        XCTAssertEqual(state.operation, .install)
        XCTAssertEqual(state.phase, .completed)
        XCTAssertEqual(state.message, "runtime install completed")
        XCTAssertNotNil(state.completedAt)
        XCTAssertEqual(stateRepository.mutations.first?.expectedRevision, nil)
        XCTAssertGreaterThan(state.revision, 1)
    }

    func testHostStateStorePreparationFailureStopsInstallBeforeProvisioningEffects() {
        let fileStore = RuntimeFileStoreSpy()
        let stateRepository = RuntimeWorkflowOperationStateRepositorySpy()
        var events: [String] = []
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let composition = RuntimeInstallComposition(
            context: RuntimeInstallCompositionContext(
                paths: LauncherPaths(
                    home: installedPaths.runtimeHome,
                    installed: installedPaths,
                    config: installedPaths.vmConfig,
                    pidFile: installedPaths.pidFile
                ),
                installedPaths: installedPaths
            ),
            operations: RuntimeInstallCompositionOperations(
                fileStore: fileStore,
                now: { Date(timeIntervalSince1970: 1_789_433_600) },
                loadInstallSettings: {
                    events.append("load-settings")
                    return "settings"
                },
                freshInstallPreflight: {
                    events.append("preflight")
                    return Self.preflight()
                },
                installProvisionPayload: { Self.provisionPayload() },
                writeRuntimeStatus: { _, _, _ in events.append("write-status") },
                writeRuntimeProgress: { _ in events.append("write-progress") },
                prepareInstallDirectories: { _ in events.append("prepare-directories") },
                rotateRuntimeLogs: { events.append("rotate-logs") },
                configureDeployEnvironment: { _ in events.append("configure-deploy") },
                prepareInstalledExecutables: { events.append("prepare-executables") },
                provisionVMDisk: { _ in events.append("provision-disk") },
                configureInstalledVMRuntime: { _ in events.append("configure-runtime") },
                createCloudInitSeed: { _ in events.append("create-seed") },
                writeInstalledRuntimeVersion: { events.append("write-version") },
                configureInstalledPermissions: { _ in events.append("configure-permissions") },
                startInstalledServices: { _ in events.append("start-services") },
                applyStartOnBootPolicy: { _ in events.append("start-on-boot") },
                waitInstallRuntimeHealth: { _ in events.append("wait-health") },
                cleanupInstallSettings: { events.append("cleanup-settings") },
                log: { _ in },
                initializeHostStateStore: {
                    events.append("initialize-state-store")
                    throw RuntimeInstallCompositionSQLiteStateTestError.databaseUnavailable
                },
                prepareHostSettings: { _ in events.append("prepare-host-settings") },
                workflowOperationStateRepository: stateRepository,
                operationID: { "install-operation-1" }
            )
        )

        XCTAssertThrowsError(try composition.install()) { error in
            XCTAssertEqual(
                error as? RuntimeInstallCompositionSQLiteStateTestError,
                .databaseUnavailable
            )
        }
        XCTAssertEqual(events, ["preflight", "initialize-state-store"])
        XCTAssertTrue(stateRepository.states.isEmpty)
    }

    private static func preflight() -> RuntimeFreshInstallPreflightDocument {
        RuntimeFreshInstallPreflightDocument(
            passed: true,
            proxyPort: 80,
            blockers: [],
            settingsState: .defaulted(path: "/private/tmp/install.json", proxyPort: 80),
            artifactStates: [.absent(path: "/usr/local/bin/vitalserver-vm")],
            serviceStates: RuntimeManagedService.uninstallOrder.map {
                RuntimeFreshInstallServiceState(label: $0.label, state: .notLoaded)
            },
            packageReceiptStates: [.absent(identifier: "ai.tirosh.vitalserver.helper")],
            proxyPortState: .clear(port: 80)
        )
    }

    private static func provisionPayload() -> RuntimeInstallProvisionPayloadDocument {
        RuntimeInstallProvisionPayloadDocument(
            passed: true,
            blockers: [],
            artifactStates: [.present(path: "/usr/local/bin/vitalserver-vm")]
        )
    }

    private func makeProvisionComposition(
        events: RuntimeInstallCompositionEventRecorder
    ) -> RuntimeInstallComposition<String> {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        return RuntimeInstallComposition(
            context: RuntimeInstallCompositionContext(
                paths: LauncherPaths(
                    home: installedPaths.runtimeHome,
                    installed: installedPaths,
                    config: installedPaths.vmConfig,
                    pidFile: installedPaths.pidFile
                ),
                installedPaths: installedPaths
            ),
            operations: RuntimeInstallCompositionOperations(
                fileStore: RuntimeFileStoreSpy(),
                now: { Date(timeIntervalSince1970: 1_789_433_600) },
                loadInstallSettings: {
                    events.values.append("load-settings")
                    return "settings"
                },
                freshInstallPreflight: { Self.preflight() },
                installProvisionPayload: { Self.provisionPayload() },
                writeRuntimeStatus: { _, _, _ in },
                writeRuntimeProgress: { _ in },
                prepareInstallDirectories: { _ in },
                rotateRuntimeLogs: {},
                configureDeployEnvironment: { _ in },
                prepareInstalledExecutables: {},
                provisionVMDisk: { _ in },
                configureInstalledVMRuntime: { _ in },
                createCloudInitSeed: { _ in },
                writeInstalledRuntimeVersion: {},
                configureInstalledPermissions: { _ in },
                startInstalledServices: { _ in },
                applyStartOnBootPolicy: { _ in },
                waitInstallRuntimeHealth: { _ in },
                cleanupInstallSettings: {},
                log: { _ in },
                initializeHostStateStore: {
                    events.values.append("initialize-state-store")
                },
                prepareHostSettings: { _ in
                    events.values.append("prepare-host-settings")
                },
                workflowOperationStateRepository: RuntimeWorkflowOperationStateRepositorySpy(),
                operationID: { UUID().uuidString }
            )
        )
    }
}

private final class RuntimeInstallCompositionEventRecorder {
    var values: [String] = []
}

private enum RuntimeInstallCompositionSQLiteStateTestError: Error, Equatable {
    case databaseUnavailable
}

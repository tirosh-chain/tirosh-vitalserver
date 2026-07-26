import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import Workflow
@testable import CLIHost
import XCTest

final class RuntimeLifecycleConfigurationSupportTests: XCTestCase {
    func testConfiguredVitalFilesDirectoryComesFromSQLiteDesiredPayload() throws {
        let harness = Harness()
        try harness.initializeDesiredVitalFilesDirectory(
            harness.installedPaths.helperManagedDefaultVitalFilesDirectory
        )

        XCTAssertEqual(
            harness.lifecycle.configuredVitalFilesDirectories(),
            .loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot(
                revision: 1,
                appliedRevision: nil,
                directories: [
                    RuntimeConfiguredVitalFilesDirectory(
                        source: .desired(revision: 1),
                        directory: harness.installedPaths.helperManagedDefaultVitalFilesDirectory
                    ),
                ]
            ))
        )
    }

    func testConfiguredVitalFilesDirectoriesIncludeDifferentDesiredAndAppliedSQLitePayloads() throws {
        let harness = Harness()
        let applied = URL(fileURLWithPath: "/Volumes/ClinicalData/AppliedVitalFiles")
        let desired = URL(fileURLWithPath: "/Volumes/ClinicalData/DesiredVitalFiles")
        try harness.initializeAppliedThenDesiredVitalFilesDirectories(
            applied: applied,
            desired: desired
        )

        XCTAssertEqual(
            harness.lifecycle.configuredVitalFilesDirectories(),
            .loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot(
                revision: 2,
                appliedRevision: 1,
                directories: [
                    RuntimeConfiguredVitalFilesDirectory(
                        source: .desired(revision: 2),
                        directory: desired
                    ),
                    RuntimeConfiguredVitalFilesDirectory(
                        source: .applied(revision: 1),
                        directory: applied
                    ),
                ]
            ))
        )
    }

    func testConfiguredVitalFilesDirectoriesReportMissingSQLiteOwnerState() throws {
        let harness = Harness()
        try harness.initializeHostStateDatabase()

        XCTAssertEqual(
            harness.lifecycle.configuredVitalFilesDirectories(),
            .unavailable(.hostSettingsMissing)
        )
    }

    func testConfiguredVitalFilesDirectoriesReportStrictVMConfigDecodeFailure() throws {
        let harness = Harness()
        try harness.initializeDesiredPayload(
            RuntimeHostSettingsPayload(
                vmConfigJSON: Data("{}".utf8),
                guestRuntimeConfigJSON: Data("{}".utf8),
                guestRuntimeSettingsJSON: Data("{}".utf8)
            )
        )

        guard case .unavailable(.configDecodeFailed(let source, let reason)) =
                harness.lifecycle.configuredVitalFilesDirectories() else {
            return XCTFail("expected desired VM config decode failure")
        }
        XCTAssertEqual(source, .desired(revision: 1))
        XCTAssertFalse(reason.isEmpty)
    }

    func testConfiguredVitalFilesDirectoriesDistinguishMissingEmptyAndRelativePath() throws {
        for (path, expected) in [
            (nil, RuntimeConfiguredVitalFilesDirectoriesUnavailableReason.pathMissing(
                source: .desired(revision: 1)
            )),
            ("", .pathInvalid(source: .desired(revision: 1), path: "", reason: "empty")),
            ("relative/vital-files", .pathInvalid(
                source: .desired(revision: 1),
                path: "relative/vital-files",
                reason: "relative"
            )),
        ] {
            let harness = Harness()
            try harness.initializeDesiredVitalFilesPath(path)

            XCTAssertEqual(
                harness.lifecycle.configuredVitalFilesDirectories(),
                .unavailable(expected)
            )
        }
    }

    func testConfiguredVitalFilesDirectoriesRejectInvalidAppliedPathEvenWhenDesiredIsValid() throws {
        let harness = Harness()
        try harness.initializeAppliedThenDesiredVitalFilesPaths(
            applied: "relative/applied-vital-files",
            desired: "/Volumes/ClinicalData/DesiredVitalFiles"
        )

        XCTAssertEqual(
            harness.lifecycle.configuredVitalFilesDirectories(),
            .unavailable(.pathInvalid(
                source: .applied(revision: 1),
                path: "relative/applied-vital-files",
                reason: "relative"
            ))
        )
    }

    func testSetSystemSleepPreventionReturnsWithoutCommandsWhenPlistIsMissing() throws {
        let harness = Harness()

        try harness.lifecycle.setSystemSleepPrevention(true)

        XCTAssertTrue(harness.commandRunner.commands.isEmpty)
        XCTAssertTrue(harness.serviceManager.startCalls.isEmpty)
        XCTAssertTrue(harness.serviceManager.stopCalls.isEmpty)
        XCTAssertTrue(harness.serviceManager.setEnabledCalls.isEmpty)
    }

    func testSetSystemSleepPreventionFailsWhenPlistInspectionFails() {
        let harness = Harness()
        harness.fileStore.pathStates[harness.sleepPreventionPlist.path] = .inspectFailed("permission denied")

        XCTAssertThrowsError(try harness.lifecycle.setSystemSleepPrevention(true)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "system sleep prevention service inspection failed path=\(harness.sleepPreventionPlist.path) reason=permission denied"
            )
        }
        XCTAssertTrue(harness.commandRunner.commands.isEmpty)
        XCTAssertTrue(harness.serviceManager.startCalls.isEmpty)
    }

    func testSetSystemSleepPreventionFailsWhenPlistPathStateIsUnexpected() {
        let harness = Harness()
        harness.fileStore.pathStates[harness.sleepPreventionPlist.path] = .directory

        XCTAssertThrowsError(try harness.lifecycle.setSystemSleepPrevention(false)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "system sleep prevention service path state is unexpected path=\(harness.sleepPreventionPlist.path) state=directory"
            )
        }
        XCTAssertTrue(harness.commandRunner.commands.isEmpty)
        XCTAssertTrue(harness.serviceManager.stopCalls.isEmpty)
    }

    func testSetSystemSleepPreventionDisablesLoadedServiceWhenPlistIsFile() throws {
        let harness = Harness()
        harness.fileStore.files[harness.sleepPreventionPlist] = Data()
        harness.serviceManager.states[.sleepPrevention] = .loaded

        try harness.lifecycle.setSystemSleepPrevention(false)

        XCTAssertEqual(harness.commandRunner.commands, [
            "/bin/launchctl disable system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
        XCTAssertEqual(harness.serviceManager.stopCalls, [.sleepPrevention])
        XCTAssertTrue(harness.serviceManager.startCalls.isEmpty)
    }

    private final class Harness {
        let productRoot: URL
        let installedPaths: InstalledRuntimePaths
        let fileStore = RuntimeFileStoreSpy()
        let commandRunner = CommandRunnerSpy()
        let serviceManager = ServiceManagerSpy()
        let sleepPreventionPlist: URL
        let lifecycle: RuntimeLifecycle

        init() {
            productRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("runtime-lifecycle-config-\(UUID().uuidString)")
            installedPaths = InstalledRuntimePaths(productRoot: productRoot)
            try? FileManager.default.createDirectory(
                at: installedPaths.runtimeDirectory,
                withIntermediateDirectories: true
            )
            sleepPreventionPlist = URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist(.sleepPrevention))
            lifecycle = RuntimeLifecycle(
                paths: LauncherPaths(
                    home: installedPaths.runtimeHome,
                    installed: installedPaths,
                    config: installedPaths.vmConfig,
                    pidFile: installedPaths.pidFile
                ),
                commandRunner: commandRunner,
                serviceManager: serviceManager,
                fileStore: fileStore
            )
        }

        func initializeHostStateDatabase() throws {
            _ = try SQLiteHostRuntimeStateDatabase(
                url: installedPaths.runtimeStateDatabase
            ).initialize()
        }

        func initializeDesiredVitalFilesDirectory(_ directory: URL) throws {
            try initializeDesiredVitalFilesPath(directory.path)
        }

        func initializeDesiredVitalFilesPath(_ path: String?) throws {
            var config = VMRuntimeConfig.default(paths: installedPaths)
            config.vitalFilesDirectory = path.map {
                SharedDirectoryConfig(
                    hostPath: $0,
                    tag: Constants.Defaults.vitalFilesDirectoryTag,
                    guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                    readOnly: false
                )
            }
            try initializeDesiredPayload(payload(config))
        }

        func initializeDesiredPayload(_ payload: RuntimeHostSettingsPayload) throws {
            try initializeHostStateDatabase()
            _ = try repository().initializeDesiredHostSettings(payload, desiredAt: "t1")
        }

        func initializeAppliedThenDesiredVitalFilesDirectories(
            applied: URL,
            desired: URL
        ) throws {
            try initializeAppliedThenDesiredVitalFilesPaths(
                applied: applied.path,
                desired: desired.path
            )
        }

        func initializeAppliedThenDesiredVitalFilesPaths(
            applied: String,
            desired: String
        ) throws {
            try initializeHostStateDatabase()
            let repository = repository()
            var appliedConfig = VMRuntimeConfig.default(paths: installedPaths)
            appliedConfig.vitalFilesDirectory = sharedDirectory(applied)
            let initial = try repository.initializeDesiredHostSettings(
                payload(appliedConfig),
                desiredAt: "t1"
            )
            _ = try repository.markHostSettingsMaterialized(
                revision: initial.revision,
                materializedAt: "t2"
            )
            let lifecycleRepository = SQLiteRuntimeVMLifecycleStateRepository(
                databaseURL: installedPaths.runtimeStateDatabase,
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            )
            _ = try lifecycleRepository.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
                document: RuntimeVMLifecycleDocument(
                    state: .starting,
                    operation: .configure,
                    operationID: "operation-1",
                    bootID: "run-1",
                    startedAt: "t3",
                    updatedAt: "t3"
                ),
                expectedRevision: nil
            ))
            _ = try repository.recordHostSettingsBoot(
                revision: 1,
                runID: "run-1",
                startedAt: "t3"
            )
            _ = try lifecycleRepository.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
                document: RuntimeVMLifecycleDocument(
                    state: .bootstrapping,
                    operation: .configure,
                    operationID: "operation-1",
                    bootID: "run-1",
                    startedAt: "t3",
                    updatedAt: "t4"
                ),
                expectedRevision: 1
            ))
            _ = try repository.markHostSettingsApplied(
                revision: 1,
                runID: "run-1",
                appliedAt: "t4"
            )
            var desiredConfig = appliedConfig
            desiredConfig.vitalFilesDirectory = sharedDirectory(desired)
            _ = try repository.saveDesiredHostSettings(
                payload(desiredConfig),
                expectedRevision: 1,
                desiredAt: "t5"
            )
        }

        private func repository() -> SQLiteRuntimeHostSettingsRepository {
            SQLiteRuntimeHostSettingsRepository(
                databaseURL: installedPaths.runtimeStateDatabase,
                transitionDecider: RuntimeHostSettingsActivationUseCase()
            )
        }

        private func payload(_ config: VMRuntimeConfig) throws -> RuntimeHostSettingsPayload {
            RuntimeHostSettingsPayload(
                vmConfigJSON: try JSONEncoder().encode(config),
                guestRuntimeConfigJSON: Data("{}".utf8),
                guestRuntimeSettingsJSON: Data("{}".utf8)
            )
        }

        private func sharedDirectory(_ path: String) -> SharedDirectoryConfig {
            SharedDirectoryConfig(
                hostPath: path,
                tag: Constants.Defaults.vitalFilesDirectoryTag,
                guestMountPath: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
                readOnly: false
            )
        }

        deinit {
            try? FileManager.default.removeItem(at: productRoot)
        }
    }
}

private final class CommandRunnerSpy: RuntimeCommandRunner {
    var commands: [String] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        commands.append(([executable] + arguments).joined(separator: " "))
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}

private final class ServiceManagerSpy: RuntimeServiceManager {
    var states: [RuntimeManagedService: RuntimeServiceState] = [:]
    var startCalls: [RuntimeManagedService] = []
    var stopCalls: [RuntimeManagedService] = []
    var setEnabledCalls: [(service: RuntimeManagedService, enabled: Bool)] = []

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        states[service] ?? .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        startCalls.append(service)
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        stopCalls.append(service)
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        setEnabledCalls.append((service, enabled))
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    func runtimeInstallComposition() -> RuntimeInstallComposition<RuntimeInstallSettings> {
        RuntimeInstallComposition(
            context: RuntimeInstallCompositionContext(
                paths: paths,
                installedPaths: installedPaths
            ),
            operations: RuntimeInstallCompositionOperations(
                fileStore: fileStore,
                now: { clock.now },
                loadInstallSettings: {
                    try RuntimeInstallSettings.load(
                        defaultVitalFilesDirectory: installedPaths.vitalFilesDirectory.path,
                        fileStore: fileStore
                    )
                },
                freshInstallPreflight: {
                    runtimeFreshInstallPreflight()
                },
                installProvisionPayload: {
                    RuntimeInstallProvisionPayloadPolicy.document(
                        artifactStates: RuntimeInstallArtifactStateReader.states(
                            paths: installProvisionPayloadPaths().map(\.path),
                            fileStore: fileStore
                        )
                    )
                },
                writeRuntimeStatus: runtimeStatusWriterAction(),
                writeRuntimeProgress: runtimeProgressWriterAction(),
                prepareInstallDirectories: { settings in
                    try runtimeInstallDirectoryPreparer().prepare(settings: settings)
                },
                rotateRuntimeLogs: rotateRuntimeLogs,
                configureDeployEnvironment: configureDeployEnvironment,
                prepareInstalledExecutables: prepareInstalledExecutables,
                provisionVMDisk: provisionVMDisk,
                configureInstalledVMRuntime: configureInstalledVMRuntime,
                createCloudInitSeed: createCloudInitSeed,
                writeInstalledRuntimeVersion: {
                    try runtimeVersionStore().writeInstalledVersion(version: Constants.launcherVersion)
                },
                configureInstalledPermissions: configureInstalledPermissions,
                startInstalledServices: startInstalledServices,
                applyStartOnBootPolicy: applyStartOnBootPolicy,
                waitInstallRuntimeHealth: { settings in
                    try waitForHealth(runtimeServiceRestartPolicy(settings))
                },
                cleanupInstallSettings: cleanupInstallSettings,
                log: log,
                prepareHostStateStore: {
                    let migrationResult = try SQLiteRuntimeOperationLeaseLegacyMigrator(
                        databaseURL: installedPaths.runtimeStateDatabase,
                        sourceURL: installedPaths.runtimeOperationLease,
                        fileStore: fileStore
                    ).migrate()
                    let database = SQLiteHostRuntimeStateDatabase(
                        url: installedPaths.runtimeStateDatabase,
                        fileStore: fileStore
                    )
                    let settingsRepository = SQLiteRuntimeHostSettingsRepository(
                        databaseURL: installedPaths.runtimeStateDatabase,
                        transitionDecider: RuntimeHostSettingsActivationUseCase()
                    )
                    switch settingsRepository.loadHostSettings() {
                    case .missing:
                        let payload = RuntimeHostSettingsPayload(
                            vmConfigJSON: try fileStore.readData(paths.config),
                            guestRuntimeConfigJSON: try fileStore.readData(installedPaths.guestRuntimeConfig),
                            guestRuntimeSettingsJSON: try fileStore.readData(installedPaths.guestRuntimeSettings)
                        )
                        _ = try JSONDecoder().decode(VMRuntimeConfig.self, from: payload.vmConfigJSON)
                        _ = try JSONDecoder().decode(
                            GuestRuntimeConfigDocument.self,
                            from: payload.guestRuntimeConfigJSON
                        )
                        _ = try JSONDecoder().decode(
                            GuestRuntimeSettingsDocument.self,
                            from: payload.guestRuntimeSettingsJSON
                        )
                        _ = try settingsRepository.importMaterializedHostSettings(
                            payload,
                            importedAt: ISO8601DateFormatter().string(from: clock.now)
                        )
                    case .loaded:
                        break
                    case .failed(let reason):
                        throw RuntimeHostStateStoreStartupError.failed(
                            path: installedPaths.runtimeStateDatabase.path,
                            stage: "host-settings-read",
                            reason: reason
                        )
                    }
                    switch database.loadHostStateStoreReadiness() {
                    case .loaded(let metadata):
                        log(
                            "Host runtime state store ready schemaVersion=\(metadata.schemaVersion) databaseId=\(metadata.databaseID) leaseMigration=\(migrationResult)"
                        )
                    case .missing:
                        throw RuntimeHostStateStoreStartupError.missing(
                            path: installedPaths.runtimeStateDatabase.path
                        )
                    case .failed(let failure):
                        throw RuntimeHostStateStoreStartupError.failed(
                            path: installedPaths.runtimeStateDatabase.path,
                            stage: failure.stage.rawValue,
                            reason: failure.message
                        )
                    }
                },
                workflowOperationStateRepository: SQLiteRuntimeWorkflowOperationStateRepository(
                    databaseURL: installedPaths.runtimeStateDatabase
                ),
                operationID: { UUID().uuidString.lowercased() }
            )
        )
    }
}

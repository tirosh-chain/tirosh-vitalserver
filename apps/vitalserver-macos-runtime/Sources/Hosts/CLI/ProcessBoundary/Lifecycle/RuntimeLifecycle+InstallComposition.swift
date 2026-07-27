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
                    try loadPackageProvisionSettings()
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
                initializeHostStateStore: initializeHostStateStore,
                prepareHostSettings: prepareHostSettings,
                workflowOperationStateRepository: SQLiteRuntimeWorkflowOperationStateRepository(
                    databaseURL: installedPaths.runtimeStateDatabase
                ),
                operationID: { UUID().uuidString.lowercased() },
                settleInstalledProductRelease: { operationID in
                    let release = try MakeInstalledProductReleaseUseCase()
                        .makePackageInstall(
                            productId: Constants.Product.identifier,
                            productVersion: Constants.launcherVersion,
                            runtimeVersion: Constants.launcherVersion,
                            installOperationId: operationID,
                            settledAt: ISO8601DateFormatter().string(from: clock.now)
                        )
                    try SQLiteUpdateBootstrapJournalRepository(
                        databaseURL: installedPaths.runtimeStateDatabase,
                        validate: ValidateUpdateBootstrapJournalUseCase().validate,
                        validateRelease: InstalledProductReleasePolicy.validate,
                        validateSettlement: InstalledProductReleasePolicy.validate
                    ).settlePackageInstallRelease(release)
                }
            )
        )
    }
}

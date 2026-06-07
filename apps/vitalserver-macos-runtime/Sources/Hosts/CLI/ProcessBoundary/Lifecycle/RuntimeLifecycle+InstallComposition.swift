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
                            paths: installProvisionPayloadPaths().map(\.path)
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
                log: log
            )
        )
    }
}

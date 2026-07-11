import Application
import Foundation
import InboundAdapters
import MacPlatformAgent
import OutboundAdapters
import RuntimeControl

@MainActor
final class MacRuntimeControlEnvironment: ObservableObject {
    let viewModel: RuntimeViewModel

    init(viewModel: RuntimeViewModel) {
        self.viewModel = viewModel
    }

    static func live() -> MacRuntimeControlEnvironment {
        let installedPaths = InstalledRuntimePaths.defaultInstalled
        let operationLeaseOwner = JSONFileRuntimeOperationLeaseRepository(
            url: installedPaths.runtimeOperationLease
        )
        let vmLifecycleStore = FileRuntimeVMLifecycleResourceStore(
            documentURL: installedPaths.vmLifecycle
        )
        let runtimeEndpointStore = FileRuntimeGuestAddressResourceStore(
            documentURL: installedPaths.runtimeEndpoint
        )
        let readWorker = MacRuntimeControlReadWorker(
            releaseInfo: .generated,
            operationLeaseReader: operationLeaseOwner,
            guestAddressProvider: runtimeEndpointStore,
            vmLifecycleResourceReader: vmLifecycleStore
        )
        let commandWorker = MacRuntimeControlCommandWorker(
            guestProductServiceController: RuntimeGuestProductServiceControlUseCase(),
            guestMaintenanceController: RuntimeGuestMaintenanceControlUseCase(),
            guestAddressProvider: runtimeEndpointStore
        )
        let client = MacRuntimeControlClient(
            releaseInfo: .generated,
            operationLeaseReader: operationLeaseOwner,
            guestAddressProvider: runtimeEndpointStore,
            vmLifecycleResourceReader: vmLifecycleStore,
            commandWorker: commandWorker
        )
        let localAPISettings = RuntimeControlLocalAPISettingsCoordinator.live()
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            snapshotReader: readWorker,
            localAPISettings: localAPISettings,
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell(),
            helperMessageLog: FileRuntimeHelperMessageLog()
        )
        return MacRuntimeControlEnvironment(viewModel: viewModel)
    }

    static func shouldStartRuntimeControlAPIServer() -> Bool {
        false
    }

    static func shouldServeRuntimeControlDevConsole(testEnabled: Bool) -> Bool {
        testEnabled
    }
}

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
        let operationLeaseOwner = SQLiteRuntimeOperationLeaseRepository(
            databaseURL: installedPaths.runtimeStateDatabase
        )
        let vmLifecycleStore = SQLiteRuntimeVMLifecycleResourceStore(
            databaseURL: installedPaths.runtimeStateDatabase,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        let runtimeEndpointStore = SQLiteRuntimeGuestAddressResourceStore(
            databaseURL: installedPaths.runtimeStateDatabase,
            lifecycleTransitionDecider: RuntimeVMLifecycleTransitionUseCase()
        )
        let hostSettingsRepository = SQLiteRuntimeHostSettingsRepository(
            databaseURL: installedPaths.runtimeStateDatabase,
            transitionDecider: RuntimeHostSettingsActivationUseCase()
        )
        let readWorker = MacRuntimeControlReadWorker(
            releaseInfo: .generated,
            operationLeaseReader: operationLeaseOwner,
            guestAddressProvider: runtimeEndpointStore,
            vmLifecycleResourceReader: vmLifecycleStore,
            hostSettingsReader: hostSettingsRepository
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
            hostSettingsReader: hostSettingsRepository,
            commandWorker: commandWorker
        )
        let viewModel = RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            snapshotReader: readWorker,
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

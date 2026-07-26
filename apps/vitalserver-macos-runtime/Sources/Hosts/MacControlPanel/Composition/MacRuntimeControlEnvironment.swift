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
        let apiDependencies = localPlatformAPIDependencies()
        let readWorker = MacRuntimeControlReadWorker(
            releaseInfo: .generated,
            platformStateReader: apiDependencies.platformStateReader,
            operationLeaseReader: apiDependencies.operationLeaseReader,
            guestAddressProvider: apiDependencies.guestAddressProvider,
            settingsReader: apiDependencies.settingsReader
        )
        let commandWorker = MacRuntimeControlCommandWorker(
            guestProductServiceController: RuntimeGuestProductServiceControlUseCase(),
            guestMaintenanceController: RuntimeGuestMaintenanceControlUseCase(),
            guestAddressProvider: apiDependencies.guestAddressProvider
        )
        let client = MacRuntimeControlClient(
            releaseInfo: .generated,
            platformStateReader: apiDependencies.platformStateReader,
            operationLeaseReader: apiDependencies.operationLeaseReader,
            guestAddressProvider: apiDependencies.guestAddressProvider,
            settingsReader: apiDependencies.settingsReader,
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

    private static func localPlatformAPIDependencies() -> LocalPlatformAPIDependencies {
        do {
            let baseURL = try RuntimeControlAPIAutomationEndpoint().baseURL()
            let httpClient = RuntimeControlAPILocalSessionHTTPClient()
            let localSessionTokenPlaceholder = "local-loopback-session"
            let operationLeaseReader = try RuntimeControlAPIOperationLeaseOwner(
                baseURL: baseURL,
                token: localSessionTokenPlaceholder,
                httpClient: httpClient
            )
            let guestAddressProvider = RuntimeControlAPIGuestAddressProvider {
                try RuntimeControlAPIGuestAddressOwner(
                    baseURL: baseURL,
                    token: localSessionTokenPlaceholder,
                    httpClient: httpClient
                )
            }
            let settingsReader = try RuntimeControlAPIPlatformSettingsReader(
                baseURL: baseURL,
                httpClient: httpClient
            )
            let platformStateReader = try RuntimeControlAPIPlatformStateReader(
                baseURL: baseURL,
                httpClient: httpClient
            )
            return LocalPlatformAPIDependencies(
                platformStateReader: platformStateReader,
                operationLeaseReader: operationLeaseReader,
                guestAddressProvider: guestAddressProvider,
                settingsReader: settingsReader
            )
        } catch {
            let reason = "Platform Agent API dependency initialization failed: \(error)"
            return LocalPlatformAPIDependencies(
                platformStateReader: FailedPlatformStateReader(reason: reason),
                operationLeaseReader: FailedOperationLeaseReader(reason: reason),
                guestAddressProvider: UnavailableRuntimeGuestAddressProvider(reason: reason),
                settingsReader: FailedRuntimeSettingsReader(reason: reason)
            )
        }
    }

    static func shouldStartRuntimeControlAPIServer() -> Bool {
        false
    }

    static func shouldServeRuntimeControlDevConsole(testEnabled: Bool) -> Bool {
        testEnabled
    }
}

private struct LocalPlatformAPIDependencies {
    let platformStateReader: any PlatformStateReading
    let operationLeaseReader: any RuntimeOperationLeaseReading
    let guestAddressProvider: any RuntimeGuestAddressProvider
    let settingsReader: any RuntimeSettingsReading
}

private struct FailedPlatformStateReader: PlatformStateReading {
    let reason: String

    func loadPlatformState(settings _: RuntimeSettings) -> PlatformState {
        failedState(source: "platformState")
    }

    func loadHealthStatus(settings _: RuntimeSettings) async -> PlatformState {
        failedState(source: "platformHealth")
    }

    private func failedState(source: String) -> PlatformState {
        PlatformState(
            runtimeInstallationState: .inspectFailed(reason),
            readIssues: [PlatformStateReadIssue(source: source, message: reason)]
        )
    }
}

private struct FailedOperationLeaseReader: RuntimeOperationLeaseReading {
    let reason: String

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        .failed(reason)
    }
}

private struct FailedRuntimeSettingsReader: RuntimeSettingsReading {
    let reason: String

    func load() -> RuntimeSettings {
        RuntimeSettings(readIssues: [
            RuntimeSettingsReadIssue(source: "platformSettings", message: reason)
        ])
    }
}

import Contracts
import Foundation
import RuntimeControl

func platformState(
    runtimeInstallationState: RuntimeFileState? = nil,
    vmServiceLoaded: Bool? = nil,
    proxyServiceLoaded: Bool? = nil,
    guestLogSyncServiceLoaded: Bool? = nil,
    sleepPreventionServiceLoaded: Bool? = nil,
    watchdogServiceLoaded: Bool? = nil,
    vmServiceState: RuntimeServiceState? = nil,
    proxyServiceState: RuntimeServiceState? = nil,
    guestLogSyncServiceState: RuntimeServiceState? = nil,
    sleepPreventionServiceState: RuntimeServiceState? = nil,
    watchdogServiceState: RuntimeServiceState? = nil,
    runtimeState: RuntimeState? = nil,
    readIssues: [PlatformStateReadIssue] = [],
    runtimeVersion: String? = nil,
    latestBackup: String? = nil,
    vmState: RuntimeVMState? = nil,
    vmErrors: [RuntimeVMError]? = nil,
    vmIP: String? = nil,
    guestHTTP: String? = nil,
    hostProxyHTTP: String? = nil,
    runtimeControlHTTP: String? = nil,
    runtimeControlStartedAt: String? = nil,
    redisUIHTTP: String? = nil,
    swaggerUIHTTP: String? = nil,
    dataStorage: ResourceUsage? = nil,
    dataStorageError: String? = nil,
    dataDirectoryStats: RuntimeDataDirectoryStats? = nil,
    dataDirectoryStatsError: String? = nil,
    proxyPort: Int? = nil,
    proxyPortReadState: RuntimeProxyPortReadState? = nil,
    failureReasons: [RuntimeFailureReason] = []
) -> PlatformState {
    let serviceInputs: [(PlatformServiceRole, RuntimeServiceState?, Bool?)] = [
        (.runtimeProvider, vmServiceState, vmServiceLoaded),
        (.publicProxy, proxyServiceState, proxyServiceLoaded),
        (.logSync, guestLogSyncServiceState, guestLogSyncServiceLoaded),
        (.sleepPrevention, sleepPreventionServiceState, sleepPreventionServiceLoaded),
        (.watchdog, watchdogServiceState, watchdogServiceLoaded),
    ]
    let services = serviceInputs.compactMap { role, state, loaded -> PlatformServiceStatus? in
        if let state {
            return PlatformServiceStatus(role: role, state: state)
        }
        if let loaded {
            return PlatformServiceStatus(role: role, state: loaded ? .loaded : .notLoaded)
        }
        return nil
    }
    let installationState = runtimeInstallationState ?? .missing

    return PlatformState(
        runtimeInstallationState: installationState,
        services: services,
        platformHealth: runtimeState,
        readIssues: readIssues,
        installedVersion: runtimeVersion,
        latestBackup: latestBackup,
        runtimeProviderState: vmState,
        runtimeProviderErrors: vmErrors,
        runtimeEndpoint: vmIP,
        runtimeControllerHTTP: guestHTTP,
        publicProxyHTTP: hostProxyHTTP,
        platformAPIHTTP: runtimeControlHTTP,
        platformAPIStartedAt: runtimeControlStartedAt,
        dataStorage: dataStorage,
        dataStorageError: dataStorageError,
        dataDirectoryStats: dataDirectoryStats,
        dataDirectoryStatsError: dataDirectoryStatsError,
        publicProxyPort: proxyPort,
        publicProxyPortReadState: proxyPortReadState,
        healthIssues: failureReasons
    )
}

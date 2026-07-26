import Contracts
import RuntimeControl

struct RuntimeLiveDiagnosticsReader {
    let runtimeLauncherPath: String
    let runtimeExecutableState: (String) -> RuntimeFileState
    let launchdServiceState: (RuntimeManagedService) -> RuntimeServiceState

    func load() -> RuntimeLiveDiagnostics {
        RuntimeLiveDiagnosticsAssembler.makeDiagnostics(
            runtimeLauncherPath: runtimeLauncherPath,
            runtimeExecutableState: runtimeExecutableState(runtimeLauncherPath),
            liveServiceStates: RuntimeLiveServiceStateReads(
                vm: launchdServiceState(.vm),
                proxy: launchdServiceState(.proxy),
                guestLogSync: launchdServiceState(.guestLogSync),
                sleepPrevention: launchdServiceState(.sleepPrevention),
                watchdog: launchdServiceState(.watchdog)
            )
        )
    }
}

import Contracts
import RuntimeControl

struct RuntimeLiveDiagnosticsReader {
    let paths: RuntimePaths
    let runtimeExecutableState: (String) -> RuntimeFileState
    let launchdServiceState: (RuntimeManagedService) -> RuntimeServiceState

    func load(statusDocument document: RuntimeStatusDocument?) -> RuntimeLiveDiagnostics {
        RuntimeLiveDiagnosticsAssembler.makeDiagnostics(
            runtimeLauncherPath: paths.launcher,
            runtimeExecutableState: runtimeExecutableState(paths.launcher),
            statusDocument: document,
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

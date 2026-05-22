import Foundation
import RuntimeCore

struct RuntimeHealthWaitRunner {
    var isLaunchdLoaded: (String) -> Bool
    var healthSnapshot: () -> RuntimeHealthSnapshot
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var sleep: () -> Void
    var log: (String) -> Void

    func wait(for policy: RuntimeServiceRestartPolicy) throws {
        guard policy.restartVM || policy.restartProxy || policy.restartWatchdog else {
            log("runtime services were not running before apply; skipping health wait")
            return
        }

        log("waiting for runtime health timeoutSeconds=\(Constants.Runtime.waitTimeoutSeconds)")
        let maxAttempts = Int(ceil(Constants.Runtime.waitTimeoutSeconds / 3.0))
        let waitResult = RuntimeHealthWaiter.wait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: maxAttempts, progressEveryAttempts: 5),
            observe: {
                RuntimeHealthWaitObservation(
                    vmServiceRequired: policy.restartVM,
                    proxyServiceRequired: policy.restartProxy,
                    watchdogServiceRequired: policy.restartWatchdog,
                    vmServiceLoaded: isLaunchdLoaded(Constants.Launchd.vmService),
                    proxyServiceLoaded: isLaunchdLoaded(Constants.Launchd.proxyService),
                    watchdogServiceLoaded: isLaunchdLoaded(Constants.Launchd.watchdogService),
                    snapshot: healthSnapshot()
                )
            },
            onProgress: { reasons in
                let reasonText = RuntimeFailureReasonText.describe(reasons)
                log("waiting for runtime health reasons=\(reasonText)")
                try? writeStatus(
                    .recovering,
                    .health,
                    "waiting for runtime health: \(reasonText)"
                )
            },
            sleep: sleep
        )

        switch waitResult {
        case .healthy:
            let snapshot = healthSnapshot()
            log("runtime health ok hostProxyHTTP=\(snapshot.hostProxyHTTP)")
        case .failedEarly(let reason):
            log("runtime health failed early reason=\(reason.rawValue)")
            throw LauncherError.runtimeHealthFailed
        case .timedOut:
            throw LauncherError.runtimeHealthFailed
        }
    }
}

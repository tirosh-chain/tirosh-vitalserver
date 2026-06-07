import Contracts
import Domain
import XCTest
import Errors

final class RuntimeHealthWaitPolicyTests: XCTestCase {
    func testWaitRequiresExplicitRequiredServiceLoadedState() {
        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 1, progressEveryAttempts: 1),
            observe: {
                RuntimeHealthWaitObservation(
                    requiredServices: [.guestLogSync],
                    serviceStates: [.guestLogSync: .readFailed("launchctl denied")],
                    snapshot: healthSnapshot(reasons: [])
                )
            },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(
            result,
            .timedOut([.guestLogSyncService("read-failed:launchctl denied")])
        )
    }

    func testWaitKeepsExplicitFailureStateWithoutFailureReasonsVisible() {
        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 1, progressEveryAttempts: 1),
            observe: {
                RuntimeHealthWaitObservation(
                    requiredServices: [],
                    serviceStates: [:],
                    snapshot: healthSnapshot(vmIP: nil, reasons: [])
                )
            },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(
            result,
            .timedOut([.unknown(RuntimeHealthSnapshotPolicy.missingFailureReasons)])
        )
    }
}

private func runRuntimeHealthWait(
    configuration: RuntimeHealthWaitConfiguration,
    observe: () -> RuntimeHealthWaitObservation,
    onProgress: ([RuntimeFailureReason]) -> Void,
    sleep: () -> Void
) -> RuntimeHealthWaitResult {
    var state = RuntimeHealthWaitState()
    for attempt in 0..<configuration.maxAttempts {
        switch RuntimeHealthWaiter.evaluateAttempt(
            configuration: configuration,
            attempt: attempt,
            state: state,
            observation: observe()
        ) {
        case .healthy:
            return .healthy
        case .failedEarly(let reason):
            return .failedEarly(reason)
        case .waiting(let nextState, let progress):
            state = nextState
            if let progress {
                onProgress(progress.reasons)
            }
            sleep()
        }
    }
    return .timedOut(state.accumulatedReasons)
}

private func healthSnapshot(
    vmIP: String? = "192.168.64.2",
    reasons: [RuntimeFailureReason]
) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: .executable,
        proxyExecutable: .executable,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: reasons.isEmpty ? .running : .unreachable,
        vmIP: vmIP,
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}

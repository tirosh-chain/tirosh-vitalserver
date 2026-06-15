import Application
import Contracts
import Domain
import XCTest
import Errors

final class RuntimeHealthWaiterTests: XCTestCase {
    func testCompletesWhenRequiredServicesAreLoadedAndSnapshotIsHealthy() {
        var sleeps = 0

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 2),
            observe: {
                RuntimeHealthWaitObservation(
                    requiredServices: [.vm, .guestLogSync, .proxy, .watchdog],
                    serviceStates: [
                        .vm: .loaded,
                        .guestLogSync: .loaded,
                        .proxy: .loaded,
                        .watchdog: .loaded,
                    ],
                    snapshot: healthySnapshot()
                )
            },
            onProgress: { _ in XCTFail("healthy wait should not publish progress") },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .healthy)
        XCTAssertEqual(sleeps, 0)
    }

    func testRequiredServiceMustLoadBeforeSnapshotIsAccepted() {
        var observations = [
            observation(vmLoaded: false, snapshot: healthySnapshot()),
            observation(vmLoaded: true, snapshot: healthySnapshot()),
        ]
        var progressReasons: [[RuntimeFailureReason]] = []
        var sleeps = 0

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 5),
            observe: { observations.removeFirst() },
            onProgress: { progressReasons.append($0) },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .healthy)
        XCTAssertEqual(progressReasons, [[.vmService("not-loaded")]])
        XCTAssertEqual(sleeps, 1)
    }

    func testRequiredGuestLogSyncServiceMustLoadBeforeSnapshotIsAccepted() {
        var observations = [
            observation(guestLogSyncLoaded: false, snapshot: healthySnapshot()),
            observation(guestLogSyncLoaded: true, snapshot: healthySnapshot()),
        ]
        var progressReasons: [[RuntimeFailureReason]] = []
        var sleeps = 0

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 5),
            observe: { observations.removeFirst() },
            onProgress: { progressReasons.append($0) },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .healthy)
        XCTAssertEqual(progressReasons, [[.guestLogSyncService("not-loaded")]])
        XCTAssertEqual(sleeps, 1)
    }

    func testRequiredServiceReadFailuresRemainDistinctFromNotLoaded() {
        var progressReasons: [[RuntimeFailureReason]] = []

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 1, progressEveryAttempts: 1),
            observe: {
                observation(
                    vmState: .readFailed("exitCode=1 stderr=operation not permitted"),
                    snapshot: healthySnapshot()
                )
            },
            onProgress: { progressReasons.append($0) },
            sleep: {}
        )

        XCTAssertEqual(
            result,
            .timedOut([.vmService("read-failed:exitCode=1 stderr=operation not permitted")])
        )
        XCTAssertEqual(
            progressReasons,
            [[.vmService("read-failed:exitCode=1 stderr=operation not permitted")]]
        )
    }

    func testMissingRequiredServiceStateRemainsDistinctFromNotLoaded() {
        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 1, progressEveryAttempts: 1),
            observe: {
                RuntimeHealthWaitObservation(
                    requiredServices: [.proxy],
                    serviceStates: [:],
                    snapshot: healthySnapshot()
                )
            },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(result, .timedOut([.proxyService("missing")]))
    }

    func testRequiredServicePendingKeepsSnapshotFailureReasonsObservable() {
        var progressReasons: [[RuntimeFailureReason]] = []
        var sleeps = 0

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            observe: {
                observation(
                    vmLoaded: false,
                    snapshot: unhealthySnapshot(reasons: [.hostProxyHTTP("502")])
                )
            },
            onProgress: { progressReasons.append($0) },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .timedOut([.vmService("not-loaded"), .hostProxyHTTP("502")]))
        XCTAssertEqual(progressReasons, [
            [.vmService("not-loaded"), .hostProxyHTTP("502")],
            [.vmService("not-loaded"), .hostProxyHTTP("502")],
        ])
        XCTAssertEqual(sleeps, 2)
    }

    func testGuestBootstrapFailureFailsEarlyEvenWhenRequiredServiceIsPending() {
        var sleeps = 0

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 1),
            observe: {
                observation(
                    vmLoaded: false,
                    snapshot: unhealthySnapshot(reasons: [
                        .vmService("not-loaded"),
                        .guestBootstrapFailed,
                    ])
                )
            },
            onProgress: { _ in XCTFail("bootstrap failure should fail before progress") },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .failedEarly(.guestBootstrapFailed))
        XCTAssertEqual(sleeps, 0)
    }

    func testGuestBootstrapFailureFailsEarly() {
        var sleeps = 0

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 1),
            observe: {
                observation(snapshot: unhealthySnapshot(reasons: [
                    .guestHTTP(RuntimeHTTPStatusText.bootstrapPending),
                    .guestBootstrapMissingRuntimePackages,
                ]))
            },
            onProgress: { _ in XCTFail("bootstrap failure should fail before progress") },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .failedEarly(.guestBootstrapMissingRuntimePackages))
        XCTAssertEqual(sleeps, 0)
    }

    func testTimesOutWithAccumulatedReasonsAndProgressCadence() {
        var attempt = 0
        var progressReasons: [[RuntimeFailureReason]] = []
        var sleeps = 0

        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 4, progressEveryAttempts: 2),
            observe: {
                defer { attempt += 1 }
                return observation(snapshot: unhealthySnapshot(reasons: [.hostProxyHTTP("\(500 + attempt)")]))
            },
            onProgress: { progressReasons.append($0) },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .timedOut([
            .hostProxyHTTP("500"),
            .hostProxyHTTP("501"),
            .hostProxyHTTP("502"),
            .hostProxyHTTP("503"),
        ]))
        XCTAssertEqual(progressReasons, [
            [.hostProxyHTTP("500")],
            [.hostProxyHTTP("502")],
        ])
        XCTAssertEqual(sleeps, 4)
    }

    func testMissingSnapshotFailureReasonsRemainObservableOnTimeout() {
        let result = runRuntimeHealthWait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 1, progressEveryAttempts: 1),
            observe: {
                observation(snapshot: unhealthySnapshot(
                    vmIP: nil,
                    reasons: []
                ))
            },
            onProgress: { _ in },
            sleep: {}
        )

        XCTAssertEqual(
            result,
            .timedOut([.unknown(RuntimeHealthSnapshotPolicy.missingFailureReasons)])
        )
    }

    private func observation(
        vmLoaded: Bool = true,
        guestLogSyncLoaded: Bool = true,
        proxyLoaded: Bool = true,
        watchdogLoaded: Bool = true,
        vmState: RuntimeServiceState? = nil,
        guestLogSyncState: RuntimeServiceState? = nil,
        proxyState: RuntimeServiceState? = nil,
        watchdogState: RuntimeServiceState? = nil,
        snapshot: RuntimeHealthSnapshot
    ) -> RuntimeHealthWaitObservation {
        RuntimeHealthWaitObservation(
            requiredServices: [.vm, .guestLogSync, .proxy, .watchdog],
            serviceStates: [
                .vm: vmState ?? (vmLoaded ? .loaded : .notLoaded),
                .guestLogSync: guestLogSyncState ?? (guestLogSyncLoaded ? .loaded : .notLoaded),
                .proxy: proxyState ?? (proxyLoaded ? .loaded : .notLoaded),
                .watchdog: watchdogState ?? (watchdogLoaded ? .loaded : .notLoaded),
            ],
            snapshot: snapshot
        )
    }

    private func healthySnapshot() -> RuntimeHealthSnapshot {
        unhealthySnapshot(vmIP: "192.168.64.2", reasons: [])
    }

    private func unhealthySnapshot(
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
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: reasons
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

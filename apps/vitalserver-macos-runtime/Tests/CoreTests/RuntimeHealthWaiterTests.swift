import Core
import Contracts
import XCTest

final class RuntimeHealthWaiterTests: XCTestCase {
    func testCompletesWhenRequiredServicesAreLoadedAndSnapshotIsHealthy() {
        var sleeps = 0

        let result = RuntimeHealthWaiter.wait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 2),
            observe: {
                RuntimeHealthWaitObservation(
                    vmServiceRequired: true,
                    proxyServiceRequired: true,
                    watchdogServiceRequired: true,
                    vmServiceLoaded: true,
                    proxyServiceLoaded: true,
                    watchdogServiceLoaded: true,
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

        let result = RuntimeHealthWaiter.wait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 5),
            observe: { observations.removeFirst() },
            onProgress: { progressReasons.append($0) },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .healthy)
        XCTAssertEqual(progressReasons, [[.vmService("not-loaded")]])
        XCTAssertEqual(sleeps, 1)
    }

    func testGuestBootstrapFailureFailsEarly() {
        var sleeps = 0

        let result = RuntimeHealthWaiter.wait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 3, progressEveryAttempts: 1),
            observe: {
                observation(snapshot: unhealthySnapshot(reasons: [
                    .guestHTTP("bootstrap-pending"),
                    .guestBootstrapMissingRuntimePackages,
                ]))
            },
            onProgress: { _ in XCTFail("bootstrap failure should fail before progress") },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .failedEarly(.guestBootstrapMissingRuntimePackages))
        XCTAssertEqual(sleeps, 0)
    }

    func testTimesOutWithLastReasonsAndProgressCadence() {
        var attempt = 0
        var progressReasons: [[RuntimeFailureReason]] = []
        var sleeps = 0

        let result = RuntimeHealthWaiter.wait(
            configuration: RuntimeHealthWaitConfiguration(maxAttempts: 4, progressEveryAttempts: 2),
            observe: {
                defer { attempt += 1 }
                return observation(snapshot: unhealthySnapshot(reasons: [.hostProxyHTTP("\(500 + attempt)")]))
            },
            onProgress: { progressReasons.append($0) },
            sleep: { sleeps += 1 }
        )

        XCTAssertEqual(result, .timedOut([.hostProxyHTTP("503")]))
        XCTAssertEqual(progressReasons, [
            [.hostProxyHTTP("500")],
            [.hostProxyHTTP("502")],
        ])
        XCTAssertEqual(sleeps, 4)
    }

    private func observation(
        vmLoaded: Bool = true,
        proxyLoaded: Bool = true,
        watchdogLoaded: Bool = true,
        snapshot: RuntimeHealthSnapshot
    ) -> RuntimeHealthWaitObservation {
        RuntimeHealthWaitObservation(
            vmServiceRequired: true,
            proxyServiceRequired: true,
            watchdogServiceRequired: true,
            vmServiceLoaded: vmLoaded,
            proxyServiceLoaded: proxyLoaded,
            watchdogServiceLoaded: watchdogLoaded,
            snapshot: snapshot
        )
    }

    private func healthySnapshot() -> RuntimeHealthSnapshot {
        unhealthySnapshot(reasons: [])
    }

    private func unhealthySnapshot(reasons: [RuntimeFailureReason]) -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: reasons
        )
    }
}

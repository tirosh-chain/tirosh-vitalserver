import Contracts
import Domain
import XCTest

final class RuntimeHealthWaitPolicyTests: XCTestCase {
    func testWaitRequiresExplicitRequiredServiceLoadedState() {
        let result = RuntimeHealthWaiter.wait(
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
        let result = RuntimeHealthWaiter.wait(
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

private func healthSnapshot(
    vmIP: String? = "192.168.64.2",
    reasons: [RuntimeFailureReason]
) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: true,
        proxyExecutable: true,
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

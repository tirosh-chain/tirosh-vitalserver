import Application
import Contracts
import Core
import XCTest

final class WaitForRuntimeHealthUseCaseTests: XCTestCase {
    func testObserveBuildsExplicitWaitObservationFromServiceStatesAndSnapshot() {
        let useCase = WaitForRuntimeHealthUseCase(
            ports: RuntimeHealthWaitPorts(
                serviceStates: { services in
                    Dictionary(uniqueKeysWithValues: services.map { service in
                        (service, service == .guestLogSync ? .notLoaded : .loaded)
                    })
                },
                healthSnapshot: { healthSnapshot(reasons: []) }
            )
        )

        let observation = useCase.observe(policy: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: true,
            restartWatchdog: true
        ))

        XCTAssertTrue(observation.vmServiceRequired)
        XCTAssertTrue(observation.guestLogSyncServiceRequired)
        XCTAssertTrue(observation.proxyServiceRequired)
        XCTAssertTrue(observation.watchdogServiceRequired)
        XCTAssertTrue(observation.vmServiceLoaded)
        XCTAssertFalse(observation.guestLogSyncServiceLoaded)
        XCTAssertTrue(observation.proxyServiceLoaded)
        XCTAssertTrue(observation.watchdogServiceLoaded)
        XCTAssertEqual(observation.snapshot.hostProxyHTTP, "200")
    }

    func testMissingServiceStateIsNotTreatedAsLoaded() {
        let useCase = WaitForRuntimeHealthUseCase(
            ports: RuntimeHealthWaitPorts(
                serviceStates: { _ in [:] },
                healthSnapshot: { healthSnapshot(reasons: []) }
            )
        )

        let observation = useCase.observe(policy: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: false
        ))

        XCTAssertFalse(observation.vmServiceLoaded)
    }
}

private func healthSnapshot(reasons: [RuntimeFailureReason]) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: true,
        proxyExecutable: true,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: reasons.isEmpty ? .running : .unreachable,
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}

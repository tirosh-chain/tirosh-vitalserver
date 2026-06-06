import Application
import Contracts
import Domain
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

        XCTAssertEqual(observation.requiredServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(observation.serviceStates[.vm], .loaded)
        XCTAssertEqual(observation.serviceStates[.guestLogSync], .notLoaded)
        XCTAssertEqual(observation.serviceStates[.proxy], .loaded)
        XCTAssertEqual(observation.serviceStates[.watchdog], .loaded)
        XCTAssertEqual(observation.snapshot.hostProxyHTTP, "200")
    }

    func testMissingServiceStateStaysMissingInObservation() {
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

        XCTAssertEqual(observation.requiredServices, [.vm])
        XCTAssertNil(observation.serviceStates[.vm])
    }

    func testServiceReadFailureStaysExplicitInObservation() {
        let useCase = WaitForRuntimeHealthUseCase(
            ports: RuntimeHealthWaitPorts(
                serviceStates: { _ in [.vm: .permissionDenied("operation not permitted")] },
                healthSnapshot: { healthSnapshot(reasons: []) }
            )
        )

        let observation = useCase.observe(policy: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: false
        ))

        XCTAssertEqual(observation.serviceStates[.vm], .permissionDenied("operation not permitted"))
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

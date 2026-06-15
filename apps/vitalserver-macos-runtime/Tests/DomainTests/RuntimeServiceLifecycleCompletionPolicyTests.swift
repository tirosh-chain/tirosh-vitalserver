import Contracts
import Domain
import XCTest
import Errors

final class RuntimeServiceLifecycleCompletionPolicyTests: XCTestCase {
    func testRequiredServicesLoadedReportsMissingAndFailedStatesExplicitly() {
        let blockers = RuntimeServiceLifecycleCompletionPolicy.requiredServicesLoaded(
            [.vm, .proxy, .watchdog],
            states: [
                .vm: .loaded,
                .proxy: .readFailed("launchctl failed"),
            ]
        )

        XCTAssertEqual(blockers, [
            "launchd-service-not-loaded:label=ai.tirosh.vitalserver.helper.proxy state=read failed: launchctl failed",
            "launchd-service-state-missing:label=ai.tirosh.vitalserver.helper.watchdog",
        ])
    }

    func testServicesStoppedRequiresExplicitNotLoadedState() {
        let blockers = RuntimeServiceLifecycleCompletionPolicy.servicesStopped(
            [.vm, .sleepPrevention],
            states: [
                .vm: .notLoaded,
                .sleepPrevention: .loaded,
            ]
        )

        XCTAssertEqual(blockers, [
            "launchd-service-not-stopped:label=ai.tirosh.vitalserver.helper.sleep-prevention state=loaded",
        ])
    }

    func testCompletionHasNoBlockersWhenExpectedStatesAreExplicitlyObserved() {
        XCTAssertEqual(
            RuntimeServiceLifecycleCompletionPolicy.requiredServicesLoaded(
                [.vm],
                states: [.vm: .loaded]
            ),
            []
        )
        XCTAssertEqual(
            RuntimeServiceLifecycleCompletionPolicy.servicesStopped(
                [.vm],
                states: [.vm: .notLoaded]
            ),
            []
        )
    }
}

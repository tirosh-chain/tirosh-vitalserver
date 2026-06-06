import Application
import Contracts
import Domain
import XCTest
import Errors

final class ControlRuntimeServicesUseCaseTests: XCTestCase {
    func testPlanOwnsServiceControlOperationIntentAndCompletionServices() {
        let useCase = ControlRuntimeServicesUseCase()

        let repair = useCase.plan(.repairAll)
        let start = useCase.plan(.startAll)
        let stop = useCase.plan(.stopAll)

        XCTAssertEqual(repair.operation, .repairServices)
        XCTAssertEqual(repair.startPolicy, RuntimeRequiredServicePolicy.allRuntimeServices)
        XCTAssertEqual(repair.stopServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(repair.requiredStartedServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(repair.requiredStoppedServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(repair.requestedLogMessage, "runtime services repair requested")
        XCTAssertEqual(
            repair.requestedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "runtime services repair requested",
                status: .recovering,
                operation: .repairServices,
                statusMessage: "runtime services repair requested"
            )
        )
        XCTAssertEqual(
            repair.completedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "runtime services repair dispatched",
                status: .recovering,
                operation: .repairServices,
                statusMessage: "runtime services repair dispatched"
            )
        )

        XCTAssertEqual(start.operation, .startServices)
        XCTAssertEqual(start.startPolicy, RuntimeRequiredServicePolicy.allRuntimeServices)
        XCTAssertEqual(start.stopServices, [])
        XCTAssertEqual(start.requiredStartedServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(start.requiredStoppedServices, [])
        XCTAssertEqual(start.requestedLogMessage, "runtime services start requested")
        XCTAssertEqual(
            start.requestedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "runtime services start requested",
                status: .recovering,
                operation: .startServices,
                statusMessage: "runtime services start requested"
            )
        )
        XCTAssertEqual(
            start.completedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "runtime services start dispatched",
                status: .recovering,
                operation: .startServices,
                statusMessage: "runtime services start dispatched"
            )
        )

        XCTAssertEqual(stop.operation, .stopServices)
        XCTAssertNil(stop.startPolicy)
        XCTAssertEqual(stop.stopServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(stop.requiredStartedServices, [])
        XCTAssertEqual(stop.requiredStoppedServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(stop.requestedLogMessage, "runtime services stop requested")
        XCTAssertNil(stop.requestedStatusPlan)
        XCTAssertEqual(
            stop.completedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "runtime services stopped",
                status: .degraded,
                operation: .stopServices,
                statusMessage: "runtime services stopped"
            )
        )
    }

    func testRequireServicesLoadedFailsWhenRequiredServiceIsNotLoaded() {
        let useCase = ControlRuntimeServicesUseCase()
        let observation = useCase.observation(states: [
            .vm: .loaded,
            .guestLogSync: .loaded,
            .proxy: .notLoaded,
            .watchdog: .loaded,
        ])

        XCTAssertThrowsError(try useCase.requireServicesLoaded(
            [.vm, .guestLogSync, .proxy, .watchdog],
            observation: observation
        )) { error in
            XCTAssertEqual(
                error as? RuntimeServiceControlError,
                .operationFailed(
                    "launchd-service-not-loaded:label=\(RuntimeManagedService.proxy.label) state=not loaded"
                )
            )
        }
    }

    func testRequireServicesStoppedFailsWhenRequiredServiceIsStillLoaded() {
        let useCase = ControlRuntimeServicesUseCase()
        let observation = useCase.observation(states: [
            .proxy: .loaded,
            .watchdog: .notLoaded,
        ])

        XCTAssertThrowsError(try useCase.requireServicesStopped(
            [.proxy, .watchdog],
            observation: observation
        )) { error in
            XCTAssertEqual(
                error as? RuntimeServiceControlError,
                .operationFailed(
                    "launchd-service-not-stopped:label=\(RuntimeManagedService.proxy.label) state=loaded"
                )
            )
        }
    }

    func testRequireStartPolicyFailsExplicitlyWhenPlanHasNoStartPolicy() {
        let useCase = ControlRuntimeServicesUseCase()
        let plan = useCase.plan(.stopAll)

        XCTAssertThrowsError(try useCase.requireStartPolicy(in: plan, operationName: "stop")) { error in
            XCTAssertEqual(
                error as? RuntimeServiceControlError,
                .operationFailed("runtime service stop plan missing start policy")
            )
        }
    }
}

import Application
import Contracts
import Domain
import XCTest
import Errors

final class ControlRuntimeServicesUseCaseTests: XCTestCase {
    func testPlanOwnsServiceControlOperationIntentAndCompletionServices() {
        let useCase = ControlRuntimeServicesUseCase()

        let repair = useCase.plan(.repairAll)
        let repairProxy = useCase.plan(.repairProxy)
        let start = useCase.plan(.startAll)
        let stop = useCase.plan(.stopAll)

        XCTAssertEqual(repair.operation, .repairServices)
        XCTAssertEqual(repair.startPolicy, RuntimeRequiredServicePolicy.allRuntimeServices)
        XCTAssertEqual(repair.stopServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(repair.requiredStartedServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(repair.requiredStoppedServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(repair.requestedLogMessage, "host runtime services repair requested")
        XCTAssertEqual(
            repair.requestedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "host runtime services repair requested",
                status: .recovering,
                operation: .repairServices,
                statusMessage: "host runtime services repair requested"
            )
        )
        XCTAssertEqual(
            repair.completedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "host runtime services repaired",
                status: .healthy,
                operation: .repairServices,
                statusMessage: "host runtime services repaired"
            )
        )

        XCTAssertEqual(repairProxy.operation, .repairProxy)
        XCTAssertEqual(
            repairProxy.startPolicy,
            RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: true,
                restartWatchdog: false
            )
        )
        XCTAssertEqual(repairProxy.stopServices, [.proxy])
        XCTAssertEqual(repairProxy.requiredStartedServices, [.proxy])
        XCTAssertEqual(repairProxy.requiredStoppedServices, [.proxy])
        XCTAssertEqual(repairProxy.requestedLogMessage, "host proxy repair requested")
        XCTAssertEqual(
            repairProxy.requestedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "host proxy repair requested",
                status: .recovering,
                operation: .repairProxy,
                statusMessage: "host proxy repair requested"
            )
        )
        XCTAssertEqual(
            repairProxy.completedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "host proxy repaired",
                status: .healthy,
                operation: .repairProxy,
                statusMessage: "host proxy repaired"
            )
        )

        XCTAssertEqual(start.operation, .startServices)
        XCTAssertEqual(start.startPolicy, RuntimeRequiredServicePolicy.allRuntimeServices)
        XCTAssertEqual(start.stopServices, [])
        XCTAssertEqual(start.requiredStartedServices, [.vm, .guestLogSync, .proxy, .watchdog])
        XCTAssertEqual(start.requiredStoppedServices, [])
        XCTAssertEqual(start.requestedLogMessage, "host runtime services start requested")
        XCTAssertEqual(
            start.requestedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "host runtime services start requested",
                status: .recovering,
                operation: .startServices,
                statusMessage: "host runtime services start requested"
            )
        )
        XCTAssertEqual(
            start.completedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "host runtime services started",
                status: .healthy,
                operation: .startServices,
                statusMessage: "host runtime services started"
            )
        )

        XCTAssertEqual(stop.operation, .stopServices)
        XCTAssertNil(stop.startPolicy)
        XCTAssertEqual(stop.stopServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(stop.requiredStartedServices, [])
        XCTAssertEqual(stop.requiredStoppedServices, RuntimeManagedService.stopOrder)
        XCTAssertEqual(stop.requestedLogMessage, "host runtime services stop requested")
        XCTAssertNil(stop.requestedStatusPlan)
        XCTAssertEqual(
            stop.completedStatusPlan,
            RuntimeServiceControlStatusPlan(
                logMessage: "host runtime services stopped",
                status: .degraded,
                operation: .stopServices,
                statusMessage: "host runtime services stopped"
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

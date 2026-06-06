import Application
import Contracts
import Domain
import XCTest
import Errors

final class InstallRuntimeUseCaseTests: XCTestCase {
    func testPlanOwnsFullInstallOperationIntent() {
        let useCase = InstallRuntimeUseCase()

        let plan = useCase.plan(for: InstallRuntimeRequest(mode: .full))

        XCTAssertEqual(plan.mode, .full)
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.install)
        XCTAssertEqual(plan.completionStatus, .healthy)
        XCTAssertEqual(plan.completionMessage, "runtime install completed")
    }

    func testPlanOwnsProvisionInstallOperationIntent() {
        let useCase = InstallRuntimeUseCase()

        let plan = useCase.plan(for: InstallRuntimeRequest(mode: .provision))

        XCTAssertEqual(plan.mode, .provision)
        XCTAssertEqual(plan.operationPlan, RuntimeOperationPlans.installProvision)
        XCTAssertEqual(plan.completionStatus, .degraded)
        XCTAssertEqual(plan.completionMessage, "runtime install provisioned; runtime services starting")
    }

    func testTransitionReturnsExplicitDecisionWithoutPersistingState() throws {
        let useCase = InstallRuntimeUseCase()

        let plan = useCase.plan(for: InstallRuntimeRequest(mode: .full))
        let decision = try useCase.transition(
            from: .notStarted,
            event: .start,
            context: RuntimeInstallTransitionContext(mode: plan.mode, plan: plan.operationPlan),
            expectedCommands: [.loadSettings]
        )

        XCTAssertEqual(decision.state, .started)
        XCTAssertEqual(decision.persistedState, .started)
        XCTAssertEqual(decision.message, "runtime install started")
        XCTAssertEqual(decision.commands, [.loadSettings])
    }

    func testSetupReadCommandsAreOwnedByUseCase() throws {
        let useCase = InstallRuntimeUseCase()

        XCTAssertEqual(
            try useCase.setupReadCommands(for: useCase.plan(for: InstallRuntimeRequest(mode: .full))),
            [.readFreshInstallPreflight]
        )
        XCTAssertEqual(
            try useCase.setupReadCommands(for: useCase.plan(for: InstallRuntimeRequest(mode: .provision))),
            [.readProvisionPayload]
        )
        XCTAssertThrowsError(try useCase.setupReadCommands(for: useCase.plan(for: InstallRuntimeRequest(
            mode: .unknown("future")
        )))) { error in
            XCTAssertEqual(
                error as? InstallRuntimeUseCaseError,
                .operationFailed("install mode unknown value=future")
            )
        }
    }

    func testUseCaseOwnsInstallWorkflowMessagesAndProgressEvents() {
        let useCase = InstallRuntimeUseCase()
        let plan = useCase.plan(for: InstallRuntimeRequest(mode: .full))
        let start = useCase.startPlan(runtimeHomePath: "/runtime")
        let event = useCase.stepProgressEvent(
            step: .startInstalledServices,
            stepStatus: .started,
            phase: .running,
            message: useCase.stepStartedMessage(.startInstalledServices)
        )

        XCTAssertEqual(start.logMessage, "runtime install started home=/runtime")
        XCTAssertEqual(start.statusMessage, "runtime install started")
        XCTAssertEqual(useCase.setupBlockedStatusMessage(blockers: ["missing-settings"]), "runtime install setup blocked: missing-settings")
        XCTAssertEqual(useCase.setupBlockedFailureMessage(blockers: ["missing-settings"]), "runtime install setup blocked blockers=missing-settings")
        XCTAssertEqual(
            useCase.missingCommandMessage(state: .preflightVerified),
            "install workflow missing command state=preflightVerified"
        )
        XCTAssertEqual(
            useCase.postSetupCommandFailureMessage(.loadSettings),
            "install workflow command appeared after setup command=loadSettings"
        )
        XCTAssertEqual(
            useCase.unknownInstallModeFailureMessage(.unknown("future")),
            "install mode unknown value=future"
        )
        XCTAssertEqual(useCase.completionLogMessage(plan: plan, runtimeHomePath: "/runtime"), "runtime install completed home=/runtime")
        XCTAssertEqual(event.operation, .install)
        XCTAssertEqual(event.status, .installing)
        XCTAssertEqual(event.step, .startInstalledServices)
        XCTAssertEqual(event.message, "step started: start-installed-services")
        XCTAssertEqual(useCase.stepCompletedMessage(.startInstalledServices), "step completed: start-installed-services")
        XCTAssertEqual(useCase.stepCompletedLogMessage(.startInstalledServices), "step=start-installed-services status=completed")
    }

    func testFreshInstallPreflightDocumentPreservesExplicitInputStatesWithoutWorkflowPolicyCall() {
        let useCase = InstallRuntimeUseCase()

        let document = useCase.freshInstallPreflightDocument(
            settingsState: .defaulted(path: "/settings.json", proxyPort: 80),
            artifactStates: [.absent(path: "/usr/local/bin/vitalserver-vm")],
            serviceStates: RuntimeManagedService.stopOrder.map { service in
                RuntimeFreshInstallServiceState(label: service.label, state: .notLoaded)
            },
            packageReceiptStates: [.absent(identifier: "ai.tirosh.vitalserver.helper")],
            proxyPortState: nil
        )

        XCTAssertFalse(document.passed)
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertEqual(document.proxyPortState, nil)
        XCTAssertEqual(document.blockers, ["host-proxy-port-state-missing:port=80"])
    }

    func testSetupObservationCommandsUseFirstPlanStepOnlyWhenExplicitlyPassed() throws {
        let useCase = InstallRuntimeUseCase()
        let fullPlan = useCase.plan(for: InstallRuntimeRequest(mode: .full))
        let provisionPlan = useCase.plan(for: InstallRuntimeRequest(mode: .provision))

        XCTAssertEqual(
            try useCase.expectedCommandsAfterFreshInstallPreflight(
                preflightDocument(passed: true, blockers: []),
                plan: fullPlan
            ),
            [.executeStep(.loadInstallSettings)]
        )
        XCTAssertEqual(
            try useCase.expectedCommandsAfterFreshInstallPreflight(
                preflightDocument(passed: false, blockers: []),
                plan: fullPlan
            ),
            []
        )
        XCTAssertEqual(
            try useCase.expectedCommandsAfterFreshInstallPreflight(
                preflightDocument(passed: true, blockers: ["existing-runtime"]),
                plan: fullPlan
            ),
            []
        )
        XCTAssertEqual(
            try useCase.expectedCommandsAfterProvisionPayload(
                provisionPayloadDocument(passed: true, blockers: []),
                plan: provisionPlan
            ),
            [.executeStep(.loadInstallSettings)]
        )
        XCTAssertEqual(
            try useCase.expectedCommandsAfterProvisionPayload(
                provisionPayloadDocument(passed: false, blockers: []),
                plan: provisionPlan
            ),
            []
        )
    }

    func testSetupObservationCommandsRejectWrongModeWithoutFallback() {
        let useCase = InstallRuntimeUseCase()
        let fullPlan = useCase.plan(for: InstallRuntimeRequest(mode: .full))
        let provisionPlan = useCase.plan(for: InstallRuntimeRequest(mode: .provision))

        XCTAssertThrowsError(try useCase.expectedCommandsAfterFreshInstallPreflight(
            preflightDocument(),
            plan: provisionPlan
        )) { error in
            XCTAssertEqual(
                error as? InstallRuntimeUseCaseError,
                .operationFailed("provision install must not use fresh install preflight")
            )
        }
        XCTAssertThrowsError(try useCase.expectedCommandsAfterProvisionPayload(
            provisionPayloadDocument(),
            plan: fullPlan
        )) { error in
            XCTAssertEqual(
                error as? InstallRuntimeUseCaseError,
                .operationFailed("full install must use fresh install preflight")
            )
        }
    }

    func testSetupObservationCommandsCompleteWhenPlanHasNoSteps() throws {
        let useCase = InstallRuntimeUseCase()
        let emptyPlan = try RuntimeOperationPlan(operation: .install, steps: [])
        let installPlan = InstallRuntimePlan(
            mode: .full,
            operationPlan: emptyPlan,
            completionStatus: .healthy,
            completionMessage: "done"
        )

        XCTAssertEqual(
            try useCase.expectedCommandsAfterFreshInstallPreflight(preflightDocument(), plan: installPlan),
            [.complete]
        )
    }

    func testUnexpectedCommandsFailExplicitly() {
        let useCase = InstallRuntimeUseCase()
        let decision = RuntimeInstallTransitionDecision(
            state: .started,
            persistedState: .started,
            commands: [.loadSettings],
            blockers: [],
            message: "unexpected"
        )

        XCTAssertThrowsError(try useCase.requireCommands([], in: decision)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "unexpected install workflow commands state=started expected=[] actual=[Domain.RuntimeInstallWorkflowCommand.loadSettings]"
            )
        }
    }

    private func preflightDocument(
        passed: Bool = true,
        blockers: [String] = []
    ) -> RuntimeFreshInstallPreflightDocument {
        RuntimeFreshInstallPreflightDocument(
            passed: passed,
            proxyPort: 80,
            blockers: blockers,
            settingsState: .defaulted(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 80),
            artifactStates: [.absent(path: "/usr/local/bin/vitalserver-vm")],
            serviceStates: RuntimeManagedService.stopOrder.map { service in
                RuntimeFreshInstallServiceState(label: service.label, state: .notLoaded)
            },
            packageReceiptStates: [
                .absent(identifier: "ai.tirosh.vitalserver.helper"),
            ],
            proxyPortState: .clear(port: 80)
        )
    }

    private func provisionPayloadDocument(
        passed: Bool = true,
        blockers: [String] = []
    ) -> RuntimeInstallProvisionPayloadDocument {
        RuntimeInstallProvisionPayloadDocument(
            passed: passed,
            blockers: blockers,
            artifactStates: [.present(path: "/usr/local/bin/vitalserver-vm")]
        )
    }
}

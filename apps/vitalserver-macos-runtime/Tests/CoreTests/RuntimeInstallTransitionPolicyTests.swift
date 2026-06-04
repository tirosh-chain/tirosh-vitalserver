import Contracts
import Core
import XCTest

final class RuntimeInstallTransitionPolicyTests: XCTestCase {
    func testStartLoadsSettingsAndPersistsStarted() throws {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .notStarted,
            event: .start,
            context: fullContext()
        )

        XCTAssertEqual(decision.state, .started)
        XCTAssertEqual(decision.persistedState, .started)
        XCTAssertEqual(decision.commands, [.loadSettings])
        XCTAssertEqual(decision.message, "runtime install started")
    }

    func testFullSettingsLoadedRequestsExplicitFreshInstallPreflightRead() throws {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .started,
            event: .settingsLoaded,
            context: fullContext()
        )

        XCTAssertEqual(decision.state, .settingsLoaded)
        XCTAssertEqual(decision.persistedState, .settingsLoaded)
        XCTAssertEqual(decision.commands, [.readFreshInstallPreflight])
    }

    func testProvisionSettingsLoadedRequestsInstalledPayloadRead() throws {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .started,
            event: .settingsLoaded,
            context: provisionContext()
        )

        XCTAssertEqual(decision.state, .settingsLoaded)
        XCTAssertEqual(decision.persistedState, .settingsLoaded)
        XCTAssertEqual(decision.commands, [.readProvisionPayload])
    }

    func testPreflightBlockersDoNotEmitInstallStepCommand() throws {
        let document = preflightDocument(
            passed: false,
            blockers: ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"]
        )

        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .freshInstallPreflightObserved(document),
            context: fullContext()
        )

        XCTAssertEqual(decision.state, .preflightBlocked)
        XCTAssertEqual(decision.persistedState, .preflightBlocked)
        XCTAssertEqual(decision.commands, [])
        XCTAssertEqual(decision.blockers, ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"])
    }

    func testPassedPreflightEmitsFirstPlanStepCommand() throws {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .freshInstallPreflightObserved(preflightDocument()),
            context: fullContext()
        )

        XCTAssertEqual(decision.state, .preflightVerified)
        XCTAssertEqual(decision.persistedState, .preflightVerified)
        XCTAssertEqual(decision.commands, [.executeStep(.loadInstallSettings)])
    }

    func testProvisionPayloadPresentEmitsFirstPlanStepCommand() throws {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .provisionPayloadObserved(provisionPayloadDocument()),
            context: provisionContext()
        )

        XCTAssertEqual(decision.state, .provisionPayloadVerified)
        XCTAssertEqual(decision.persistedState, .provisionPayloadVerified)
        XCTAssertEqual(decision.commands, [.executeStep(.loadInstallSettings)])
    }

    func testProvisionPayloadMissingBlocksWithoutExecutingInstallStep() throws {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .provisionPayloadObserved(provisionPayloadDocument(
                passed: false,
                blockers: ["install-payload-missing:path=/usr/local/bin/vitalserver-vm"],
                artifactStates: [.absent(path: "/usr/local/bin/vitalserver-vm")]
            )),
            context: provisionContext()
        )

        XCTAssertEqual(decision.state, .provisionPayloadBlocked)
        XCTAssertEqual(decision.persistedState, .provisionPayloadBlocked)
        XCTAssertEqual(decision.commands, [])
        XCTAssertEqual(decision.blockers, ["install-payload-missing:path=/usr/local/bin/vitalserver-vm"])
    }

    func testFullInstallCompletesOnlyAfterLastPlanStep() throws {
        let context = fullContext()
        let preflightDecision = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .freshInstallPreflightObserved(preflightDocument()),
            context: context
        )
        let firstStarted = try RuntimeInstallTransitionPolicy.transition(
            from: preflightDecision.state,
            event: .stepStarted(.loadInstallSettings),
            context: context
        )

        XCTAssertEqual(firstStarted.state, .stepStarted(.loadInstallSettings))
        XCTAssertEqual(firstStarted.persistedState, .stepStarted)
        XCTAssertEqual(firstStarted.currentStep, .loadInstallSettings)
        XCTAssertEqual(firstStarted.commands, [])

        var state = firstStarted.state
        for step in RuntimeOperationPlans.install.steps {
            if state != .stepStarted(step) {
                state = try RuntimeInstallTransitionPolicy.transition(
                    from: state,
                    event: .stepStarted(step),
                    context: context
                ).state
            }
            let decision = try RuntimeInstallTransitionPolicy.transition(
                from: state,
                event: .stepSucceeded(step),
                context: context
            )
            state = decision.state
            if step == RuntimeOperationPlans.install.steps.last {
                XCTAssertEqual(decision.state, .completed)
                XCTAssertEqual(decision.persistedState, .completed)
                XCTAssertEqual(decision.commands, [.complete])
            } else {
                let nextIndex = RuntimeOperationPlans.install.steps.firstIndex(of: step)! + 1
                let next = RuntimeOperationPlans.install.steps[nextIndex]
                XCTAssertEqual(decision.state, .stepCompleted(step))
                XCTAssertEqual(decision.persistedState, .stepCompleted)
                XCTAssertEqual(decision.currentStep, step)
                XCTAssertEqual(decision.commands, [.executeStep(next)])
            }
        }
    }

    func testProvisionInstallCompletesProvisionedWithoutHealthStep() throws {
        let context = provisionContext()
        var state = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .provisionPayloadObserved(provisionPayloadDocument()),
            context: context
        ).state

        for step in RuntimeOperationPlans.installProvision.steps {
            state = try RuntimeInstallTransitionPolicy.transition(
                from: state,
                event: .stepStarted(step),
                context: context
            ).state
            let decision = try RuntimeInstallTransitionPolicy.transition(
                from: state,
                event: .stepSucceeded(step),
                context: context
            )
            state = decision.state
            if step == RuntimeOperationPlans.installProvision.steps.last {
                XCTAssertEqual(decision.state, .provisioned)
                XCTAssertEqual(decision.persistedState, .provisioned)
                XCTAssertEqual(decision.commands, [.complete])
            }
        }
    }

    func testStepFailurePersistsFailedWithExplicitBlocker() throws {
        let decision = try RuntimeInstallTransitionPolicy.transition(
            from: .stepStarted(.provisionVMDisk),
            event: .stepFailed(.provisionVMDisk, reason: "disk full"),
            context: fullContext()
        )

        XCTAssertEqual(decision.state, .failed)
        XCTAssertEqual(decision.persistedState, .failed)
        XCTAssertEqual(decision.currentStep, .provisionVMDisk)
        XCTAssertEqual(decision.blockers, ["install-step-failed:step=provision-vm-disk reason=disk full"])
        XCTAssertEqual(decision.commands, [])
    }

    func testCannotStartOutOfOrderStep() throws {
        XCTAssertThrowsError(try RuntimeInstallTransitionPolicy.transition(
            from: .preflightVerified,
            event: .stepStarted(.provisionVMDisk),
            context: fullContext()
        )) { error in
            XCTAssertTrue(error is RuntimeInstallTransitionError)
        }
    }

    func testFullInstallPlanMustContainHealthWait() throws {
        XCTAssertThrowsError(try RuntimeInstallTransitionPolicy.transition(
            from: .notStarted,
            event: .start,
            context: RuntimeInstallTransitionContext(
                mode: .full,
                plan: RuntimeOperationPlans.installProvision
            )
        )) { error in
            XCTAssertTrue(String(describing: error).contains("full install plan must wait for runtime health"))
        }
    }

    func testProvisionInstallPlanMustNotClaimRuntimeHealth() throws {
        XCTAssertThrowsError(try RuntimeInstallTransitionPolicy.transition(
            from: .notStarted,
            event: .start,
            context: RuntimeInstallTransitionContext(
                mode: .provision,
                plan: RuntimeOperationPlans.install
            )
        )) { error in
            XCTAssertTrue(String(describing: error).contains("install provision plan must not claim runtime health"))
        }
    }

    private func fullContext() -> RuntimeInstallTransitionContext {
        RuntimeInstallTransitionContext(mode: .full, plan: RuntimeOperationPlans.install)
    }

    private func provisionContext() -> RuntimeInstallTransitionContext {
        RuntimeInstallTransitionContext(mode: .provision, plan: RuntimeOperationPlans.installProvision)
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
            serviceStates: freshInstallServiceStates(),
            packageReceiptStates: [
                .absent(identifier: "com.tirosh.vitalserver.vm"),
                .absent(identifier: "com.tirosh.vitalserver"),
            ],
            proxyPortState: .clear(port: 80)
        )
    }

    private func provisionPayloadDocument(
        passed: Bool = true,
        blockers: [String] = [],
        artifactStates: [RuntimeInstallArtifactState] = [.present(path: "/usr/local/bin/vitalserver-vm")]
    ) -> RuntimeInstallProvisionPayloadDocument {
        RuntimeInstallProvisionPayloadDocument(
            passed: passed,
            blockers: blockers,
            artifactStates: artifactStates
        )
    }

    private func freshInstallServiceStates() -> [RuntimeFreshInstallServiceState] {
        RuntimeManagedService.stopOrder.map { service in
            RuntimeFreshInstallServiceState(label: service.label, state: .notLoaded)
        }
    }
}

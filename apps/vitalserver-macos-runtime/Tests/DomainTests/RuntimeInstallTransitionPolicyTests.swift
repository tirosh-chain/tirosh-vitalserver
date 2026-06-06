import Contracts
import Domain
import XCTest

final class DomainRuntimeInstallTransitionPolicyTests: XCTestCase {
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

    func testFullInstallPreflightMustPassBeforeFirstStep() throws {
        let blocked = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .freshInstallPreflightObserved(preflightDocument(
                passed: false,
                blockers: ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"]
            )),
            context: fullContext()
        )

        XCTAssertEqual(blocked.state, .preflightBlocked)
        XCTAssertEqual(blocked.commands, [])
        XCTAssertEqual(blocked.blockers, ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"])

        let verified = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .freshInstallPreflightObserved(preflightDocument()),
            context: fullContext()
        )

        XCTAssertEqual(verified.state, .preflightVerified)
        XCTAssertEqual(verified.commands, [.executeStep(.loadInstallSettings)])
    }

    func testProvisionInstallUsesProvisionPayloadAndCompletesProvisioned() throws {
        let context = RuntimeInstallTransitionContext(mode: .provision, plan: RuntimeOperationPlans.installProvision)
        var state = try RuntimeInstallTransitionPolicy.transition(
            from: .settingsLoaded,
            event: .provisionPayloadObserved(RuntimeInstallProvisionPayloadDocument(
                passed: true,
                blockers: [],
                artifactStates: [.present(path: "/usr/local/bin/vitalserver-vm")]
            )),
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
        }

        XCTAssertEqual(state, .provisioned)
    }

    func testProvisionInstallPlanMustNotClaimRuntimeHealth() {
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
}

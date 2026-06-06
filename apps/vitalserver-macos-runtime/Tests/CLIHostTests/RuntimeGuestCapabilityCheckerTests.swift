import Contracts
import Application
import Bootstrap
import Domain
import Workflow
@testable import CLIHost
import XCTest
import Errors

final class RuntimeGuestCapabilityCheckerTests: XCTestCase {
    func testCheckerDelegatesRequirementPlanToExecutionPort() throws {
        var plans: [RuntimeGuestCapabilityRequirementPlan] = []
        let checker = RuntimeGuestCapabilityChecker(
            loadRuntimeState: {
                .loaded(GuestRuntimeStateDocument(
                    capabilities: GuestRuntimeCapabilities(
                        prepareUpdateShutdown: true,
                        activateUpdate: true,
                        redisBackup: true,
                        repairDatastore: true
                    ),
                    vmIP: "192.168.64.2",
                    guestHTTP: nil,
                    redisUIHTTP: nil,
                    swaggerUIHTTP: nil
                ))
            },
            executeRequirementPlan: { plans.append($0) }
        )

        try checker.require(.prepareUpdateShutdown)

        XCTAssertEqual(plans, [.supported])
    }

    func testRequirePassesWhenCapabilityIsSupported() throws {
        let checker = RuntimeGuestCapabilityCheckerComposition.make(
            guestGateway: RuntimeGuestCapabilityGatewaySpy(result: .loaded(supportedState()))
        )

        try checker.require(.prepareUpdateShutdown)
    }

    func testRequireFailsWhenCapabilityIsMissingFromState() {
        let checker = RuntimeGuestCapabilityCheckerComposition.make(
            guestGateway: RuntimeGuestCapabilityGatewaySpy(result: .loaded(GuestRuntimeStateDocument(
                    vmIP: "192.168.64.2",
                    guestHTTP: nil,
                    redisUIHTTP: nil,
                    swaggerUIHTTP: nil
                )))
        )

        XCTAssertThrowsError(try checker.require(.prepareUpdateShutdown)) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: prepare-update-shutdown")
        }
    }

    func testRequireFailsWhenRuntimeStateCannotBeLoaded() {
        let checker = RuntimeGuestCapabilityCheckerComposition.make(
            guestGateway: RuntimeGuestCapabilityGatewaySpy(result: .failed("permission denied"))
        )

        XCTAssertThrowsError(try checker.require(.activateUpdate)) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to read guest runtime state for guest capability activate-update: permission denied"
            )
        }
    }
}

private func supportedState() -> GuestRuntimeStateDocument {
    GuestRuntimeStateDocument(
        capabilities: GuestRuntimeCapabilities(
            prepareUpdateShutdown: true,
            activateUpdate: true,
            redisBackup: true,
            repairDatastore: true
        ),
        vmIP: "192.168.64.2",
        guestHTTP: nil,
        redisUIHTTP: nil,
        swaggerUIHTTP: nil
    )
}

private final class RuntimeGuestCapabilityGatewaySpy: RuntimeGuestGateway {
    let result: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>

    init(result: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>) {
        self.result = result
    }

    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument> {
        result
    }

    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument> { .missing }
    func removeUpdateActivationResult() throws {}
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws {}
    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument> { .missing }
    func removeUpdateShutdownResult() throws {}
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {}
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> { .missing }
    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> { .missing }
}

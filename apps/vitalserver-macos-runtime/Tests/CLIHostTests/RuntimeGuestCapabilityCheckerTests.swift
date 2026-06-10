import Contracts
import Application
import Bootstrap
@testable import CLIHost
import XCTest

final class RuntimeGuestCapabilityCheckerTests: XCTestCase {
    func testRequirePassesWhenCapabilityIsSupported() throws {
        try RuntimeGuestCapabilityCheckerComposition.require(
            .prepareUpdateShutdown,
            guestGateway: RuntimeGuestCapabilityGatewaySpy(result: .loaded(supportedState()))
        )
    }

    func testRequireFailsWhenCapabilityIsMissingFromState() {
        let gateway = RuntimeGuestCapabilityGatewaySpy(
            result: .loaded(GuestRuntimeStateDocument(
                vmIP: "192.168.64.2",
                guestHTTP: nil,
                redisUIHTTP: nil,
                swaggerUIHTTP: nil
            ))
        )

        XCTAssertThrowsError(try RuntimeGuestCapabilityCheckerComposition.require(
            .prepareUpdateShutdown,
            guestGateway: gateway
        )) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: prepare-update-shutdown")
        }
    }

    func testRequireFailsWhenRuntimeStateCannotBeLoaded() {
        XCTAssertThrowsError(try RuntimeGuestCapabilityCheckerComposition.require(
            .activateUpdate,
            guestGateway: RuntimeGuestCapabilityGatewaySpy(result: .loaded(GuestRuntimeStateDocument(
                capabilities: nil,
                vmIP: "192.168.64.2",
                guestHTTP: nil,
                redisUIHTTP: nil,
                swaggerUIHTTP: nil
            ))
        ))) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: activate-update")
        }

        XCTAssertThrowsError(try RuntimeGuestCapabilityCheckerComposition.require(
            .activateUpdate,
            guestGateway: RuntimeGuestCapabilityGatewaySpy(result: .failed("permission denied"))
        )) { error in
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
            redisRestore: true,
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
    func clearUpdateShutdownPreparation() throws {}
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws {}
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument> { .missing }
    func removeDatastoreRepairResult() throws {}
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws {}
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument> { .missing }
}

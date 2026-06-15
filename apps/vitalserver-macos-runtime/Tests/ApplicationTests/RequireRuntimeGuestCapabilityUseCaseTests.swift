import Application
import Contracts
import XCTest

final class RequireRuntimeGuestCapabilityUseCaseTests: XCTestCase {
    func testRequirePassesWhenCapabilityIsSupported() throws {
        try RequireRuntimeGuestCapabilityUseCase().require(
            .prepareUpdateShutdown,
            operations: operations(result: .loaded(supportedState()))
        )
    }

    func testRequireFailsWhenCapabilityIsMissingFromState() {
        XCTAssertThrowsError(try RequireRuntimeGuestCapabilityUseCase().require(
            .prepareUpdateShutdown,
            operations: operations(result: .loaded(GuestRuntimeStateDocument(
                vmIP: "192.168.64.2",
                guestHTTP: nil,
                redisUIHTTP: nil,
                swaggerUIHTTP: nil
            )))
        )) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: prepare-update-shutdown")
        }
    }

    func testRequireFailsWhenRuntimeStateCannotBeLoaded() {
        XCTAssertThrowsError(try RequireRuntimeGuestCapabilityUseCase().require(
            .activateUpdate,
            operations: operations(result: .failed("permission denied"))
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to read guest runtime state for guest capability activate-update: permission denied"
            )
        }
    }

    private func operations(
        result: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
    ) -> RuntimeGuestCapabilityRequirementOperations {
        RuntimeGuestCapabilityRequirementOperations(
            loadRuntimeState: { result }
        )
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

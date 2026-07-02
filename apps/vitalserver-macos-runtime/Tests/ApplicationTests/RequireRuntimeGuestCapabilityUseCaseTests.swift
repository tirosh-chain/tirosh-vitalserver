import Application
import Contracts
import XCTest

final class RequireRuntimeGuestCapabilityUseCaseTests: XCTestCase {
    func testRequirePassesWhenCapabilityIsSupported() throws {
        try RequireRuntimeGuestCapabilityUseCase().require(
            .prepareUpdateShutdown,
            operations: operations(result: .loaded(supportedCapabilities()))
        )
    }

    func testRequireFailsWhenCapabilityIsMissingFromGuestControlCapabilities() {
        XCTAssertThrowsError(try RequireRuntimeGuestCapabilityUseCase().require(
            .prepareUpdateShutdown,
            operations: operations(result: .loaded(RuntimeGuestControlCapabilities(
                schemaVersion: 1,
                capabilities: ["services:list"]
            )))
        )) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: prepare-update-shutdown")
        }
    }

    func testRequireFailsWhenGuestControlCapabilitiesCannotBeLoaded() {
        XCTAssertThrowsError(try RequireRuntimeGuestCapabilityUseCase().require(
            .activateUpdate,
            operations: operations(result: .failed("permission denied"))
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to read guest capabilities for activate-update: permission denied"
            )
        }
    }

    private func operations(
        result: RuntimeGuestCapabilityReadResult
    ) -> RuntimeGuestCapabilityRequirementOperations {
        RuntimeGuestCapabilityRequirementOperations(
            loadCapabilities: { result }
        )
    }
}

private func supportedCapabilities() -> RuntimeGuestControlCapabilities {
    RuntimeGuestControlCapabilities(
        schemaVersion: 1,
        capabilities: [
            "maintenance:update-shutdown:create",
            "maintenance:update-activation:create",
            "maintenance:redis-backup:create",
            "maintenance:redis-restore:create",
            "maintenance:datastore-repair:create",
        ]
    )
}

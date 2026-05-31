import Contracts
import Core
@testable import HostCLI
import XCTest

final class RuntimeGuestCapabilityCheckerTests: XCTestCase {
    func testRequirePassesWhenCapabilityIsSupported() throws {
        let checker = RuntimeGuestCapabilityChecker(loadRuntimeState: {
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
        })

        try checker.require(.prepareUpdateShutdown)
    }

    func testRequireFailsWhenCapabilityIsMissingFromState() {
        let checker = RuntimeGuestCapabilityChecker(loadRuntimeState: {
            .loaded(GuestRuntimeStateDocument(
                vmIP: "192.168.64.2",
                guestHTTP: nil,
                redisUIHTTP: nil,
                swaggerUIHTTP: nil
            ))
        })

        XCTAssertThrowsError(try checker.require(.prepareUpdateShutdown)) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: prepare-update-shutdown")
        }
    }

    func testRequireFailsWhenRuntimeStateCannotBeLoaded() {
        let checker = RuntimeGuestCapabilityChecker(loadRuntimeState: {
            .failed("permission denied")
        })

        XCTAssertThrowsError(try checker.require(.activateUpdate)) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to read guest runtime state for guest capability activate-update: permission denied"
            )
        }
    }
}

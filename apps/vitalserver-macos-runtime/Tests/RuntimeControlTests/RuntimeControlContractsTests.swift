import RuntimeControl
import XCTest

final class RuntimeControlContractsTests: XCTestCase {
    func testRuntimeStatePreservesUnknownValues() throws {
        let state = RuntimeState(rawValue: "maintenance")

        XCTAssertEqual(state.rawValue, "maintenance")

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeState.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("maintenance"))
    }

    func testRuntimeStatusUsesTypedOperationAndRoundTripsThroughJSON() throws {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            operation: .applyBundle,
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        XCTAssertTrue(status.isReady)

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: encoded)

        XCTAssertEqual(decoded.operation, .applyBundle)
        XCTAssertTrue(decoded.isReady)
    }
}

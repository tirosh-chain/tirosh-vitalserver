import RuntimeControl
@testable import InboundAdapters
import XCTest

final class RuntimeHostTextDisplayPolicyTests: XCTestCase {
    func testNoDataMissingUsesPresentationFallbackText() {
        let policy = RuntimeHostTextDisplayPolicy(noDataText: "No log data")

        XCTAssertEqual(policy.displayText(.missing(.noData)), "No log data")
    }

    func testExplicitMessageMissingPreservesMessage() {
        let policy = RuntimeHostTextDisplayPolicy(noDataText: "No log data")

        XCTAssertEqual(policy.displayText(.missing(.message("Missing manifest.json"))), "Missing manifest.json")
    }
}

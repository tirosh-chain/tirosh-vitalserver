import XCTest
@testable import VitalServerHelperApp

final class LegacyCommandProgressParserTests: XCTestCase {
    func testUsesNewestStructuredStepLine() {
        let content = """
        [2026-05-21T10:00:00Z] step=verify-bundle status=completed
        [2026-05-21T10:00:01Z] step=activate-guest-update status=started
        """

        XCTAssertEqual(
            LegacyCommandProgressParser.progressMessage(from: content),
            "Running: Activate Guest Update"
        )
    }

    func testRecognizesHealthWaitReasonLine() {
        let content = "[2026-05-21T10:00:00Z] waiting for runtime health reasons=guest-http-failed"

        XCTAssertEqual(
            LegacyCommandProgressParser.progressMessage(from: content),
            "Waiting for runtime health: guest-http-failed"
        )
    }

    func testReturnsNilWhenNoProgressLineExists() {
        XCTAssertNil(LegacyCommandProgressParser.progressMessage(from: "plain output\nmore plain output"))
    }
}

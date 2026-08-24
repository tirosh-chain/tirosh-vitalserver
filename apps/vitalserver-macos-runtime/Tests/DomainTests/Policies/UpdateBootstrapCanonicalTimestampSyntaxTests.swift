import Domain
import Foundation
import XCTest

final class UpdateBootstrapCanonicalTimestampSyntaxTests: XCTestCase {
    func testAcceptsWholeSecondUTCInstant() {
        XCTAssertTrue(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-08-24T00:00:00Z"
            )
        )
        XCTAssertTrue(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2024-02-29T23:59:59Z"
            )
        )
    }

    func testRejectsOffsetAndSpaceSeparatedForms() {
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-07-27 00:00:00+00:00"
            )
        )
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-07-27T00:00:00+00:00"
            )
        )
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-07-27T00:00:00+0000"
            )
        )
    }

    func testRejectsFractionalSeconds() {
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-07-27T00:00:00.0Z"
            )
        )
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-07-27T00:00:00.000Z"
            )
        )
    }

    func testRejectsInvalidCalendarDateWithoutNormalizing() {
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-02-30T00:00:00Z"
            )
        )
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-13-01T00:00:00Z"
            )
        )
    }

    func testRejectsEmptyAndNonZSuffix() {
        XCTAssertFalse(UpdateBootstrapCanonicalTimestampSyntax.isCanonical(""))
        XCTAssertFalse(
            UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
                "2026-07-27T00:00:00z"
            )
        )
    }

    func testFormatProducesTheCanonicalUTCForm() {
        let date = UpdateBootstrapCanonicalTimestampSyntax.format(
            Date(timeIntervalSince1970: 1_785_110_400)
        )

        XCTAssertEqual(date, "2026-07-27T00:00:00Z")
        XCTAssertTrue(UpdateBootstrapCanonicalTimestampSyntax.isCanonical(date))
    }
}

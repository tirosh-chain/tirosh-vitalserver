import XCTest
import Errors

final class FailureKindTests: XCTestCase {
    func testFailureKindsPreserveDistinctMeanings() {
        let meanings: Set<FailureKind> = [
            .missing,
            .invalid,
            .failed,
            .stale,
            .permissionDenied,
            .dependencyUnavailable,
            .unknown,
        ]

        XCTAssertEqual(meanings.count, 7)
    }
}

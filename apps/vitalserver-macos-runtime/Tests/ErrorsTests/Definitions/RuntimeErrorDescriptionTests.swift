import XCTest
import Errors

final class RuntimeErrorDescriptionTests: XCTestCase {
    func testDescribeUsesExplicitErrorDescriptionBoundary() {
        XCTAssertEqual(
            RuntimeErrorDescription.describe(TestRuntimeError.permissionDenied),
            "permissionDenied"
        )
    }
}

private enum TestRuntimeError: Error {
    case permissionDenied
}

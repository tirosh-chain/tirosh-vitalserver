import XCTest
import Errors

final class BoundaryFailureTests: XCTestCase {
    func testBoundaryFailureCarriesExplicitKindAndContext() {
        let failure = BoundaryFailure(
            kind: .permissionDenied,
            context: ErrorContext(
                operation: "read-runtime-status",
                source: "status-document",
                detail: "permission denied"
            )
        )

        XCTAssertEqual(failure.kind, .permissionDenied)
        XCTAssertEqual(failure.context.operation, "read-runtime-status")
        XCTAssertEqual(failure.context.source, "status-document")
        XCTAssertEqual(failure.context.detail, "permission denied")
    }
}

import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeControlStatusAnnotatorTests: XCTestCase {
    func testAnnotatesRuntimeControlHTTPAndStableStartedAt() throws {
        let startedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-30T00:01:00Z"))
        let annotator = RuntimeControlStatusAnnotator(runtimeControlStartedAt: startedAt)
        let status = RuntimeStatus(runtimeInstalled: true, runtimeState: .healthy, statusMessage: "ready")

        let annotated = annotator.annotated(status)

        XCTAssertEqual(annotated.runtimeControlHTTP, "200")
        XCTAssertEqual(annotated.runtimeControlStartedAt, "2026-05-30T00:01:00Z")
        XCTAssertEqual(annotated.statusMessage, "ready")
    }

    func testAnnotationReplacesOnlyRuntimeControlFields() throws {
        let startedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-30T00:02:00Z"))
        let annotator = RuntimeControlStatusAnnotator(runtimeControlHTTP: "204", runtimeControlStartedAt: startedAt)
        let status = RuntimeStatus(
            runtimeInstalled: true,
            runtimeState: .degraded,
            runtimeControlHTTP: "500",
            runtimeControlStartedAt: "stale"
        )

        let annotated = annotator.annotated(status)

        XCTAssertEqual(annotated.runtimeState, .degraded)
        XCTAssertEqual(annotated.runtimeControlHTTP, "204")
        XCTAssertEqual(annotated.runtimeControlStartedAt, "2026-05-30T00:02:00Z")
    }
}

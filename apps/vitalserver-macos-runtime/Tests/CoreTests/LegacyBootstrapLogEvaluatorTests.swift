import XCTest
@testable import Core
import Contracts

final class LegacyBootstrapLogEvaluatorTests: XCTestCase {
    func testMissingRuntimePackageMapsToTypedReason() {
        XCTAssertEqual(
            LegacyBootstrapLogEvaluator.failureReason(
                logContent: "error: missing runtime package in air-gapped rootfs"
            ),
            .guestBootstrapMissingRuntimePackages
        )
    }

    func testGenericErrorAndFailedMapToBootstrapFailed() {
        XCTAssertEqual(
            LegacyBootstrapLogEvaluator.failureReason(logContent: "error: compose failed"),
            .guestBootstrapFailed
        )
        XCTAssertEqual(
            LegacyBootstrapLogEvaluator.failureReason(logContent: "bootstrap failed"),
            .guestBootstrapFailed
        )
    }

    func testOnlyTailIsConsidered() {
        let staleFailure = "error: missing runtime package\n"
        let healthyTail = Array(repeating: "ok", count: 80).joined(separator: "\n")

        XCTAssertNil(LegacyBootstrapLogEvaluator.failureReason(logContent: staleFailure + healthyTail))
    }
}

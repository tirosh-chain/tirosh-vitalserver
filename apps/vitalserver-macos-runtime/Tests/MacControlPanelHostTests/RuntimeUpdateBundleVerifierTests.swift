import Foundation
import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeUpdateBundleVerifierTests: XCTestCase {
    func testVerifyFormatsSuccessfulBundleResult() async {
        let verifier = RuntimeUpdateBundleVerifier()
        let bundleURL = URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")

        let result = await verifier.verify(bundleURL: bundleURL) { url in
            XCTAssertEqual(url, bundleURL)
            return RuntimeCommandResult(exitCode: 0, stdout: "ok", stderr: "")
        }

        XCTAssertTrue(result.isVerified)
        XCTAssertEqual(result.verification, "\(AppConstants.StatusText.updateBundleIntegrityChecked)\n\nok")
        XCTAssertEqual(result.message, result.verification)
    }

    func testVerifyFormatsFailedBundleResult() async {
        let verifier = RuntimeUpdateBundleVerifier()

        let result = await verifier.verify(bundleURL: URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")) { _ in
            RuntimeCommandResult(exitCode: 1, stdout: "", stderr: "bad signature")
        }

        XCTAssertFalse(result.isVerified)
        XCTAssertEqual(
            result.verification,
            "\(AppConstants.StatusText.updateBundleVerificationFailed)\n\nbad signature"
        )
        XCTAssertEqual(result.message, result.verification)
    }

    func testVerifyReportsThrownError() async {
        let verifier = RuntimeUpdateBundleVerifier()

        let result = await verifier.verify(bundleURL: URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")) { _ in
            throw UpdateBundleVerificationError.failed
        }

        XCTAssertFalse(result.isVerified)
        XCTAssertEqual(result.verification, "Verification failed.")
        XCTAssertEqual(result.message, "Verification failed.")
    }
}

private enum UpdateBundleVerificationError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Verification failed."
    }
}

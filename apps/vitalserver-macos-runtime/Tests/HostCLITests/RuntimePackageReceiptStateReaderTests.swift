import Contracts
import Core
@testable import HostCLI
import XCTest

final class RuntimePackageReceiptStateReaderTests: XCTestCase {
    func testPkgInfoSuccessReportsReceiptPresent() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "com.tirosh.vitalserver",
            runProcess: { _, _ in RuntimeProcessResult(exitCode: 0, stdout: "package-id: com.tirosh.vitalserver\n", stderr: "") }
        )

        XCTAssertEqual(state, .present(identifier: "com.tirosh.vitalserver"))
    }

    func testExplicitNoReceiptReportsAbsent() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "com.tirosh.vitalserver",
            runProcess: { _, _ in
                RuntimeProcessResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "No receipt for 'com.tirosh.vitalserver' found at '/'.\n"
                )
            }
        )

        XCTAssertEqual(state, .absent(identifier: "com.tirosh.vitalserver"))
    }

    func testUnknownPkgInfoFailureReportsReadFailure() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "com.tirosh.vitalserver",
            runProcess: { _, _ in RuntimeProcessResult(exitCode: 2, stdout: "", stderr: "database locked\n") }
        )

        XCTAssertEqual(
            state,
            .readFailed(identifier: "com.tirosh.vitalserver", reason: "exitCode=2 stderr=database locked")
        )
    }
}

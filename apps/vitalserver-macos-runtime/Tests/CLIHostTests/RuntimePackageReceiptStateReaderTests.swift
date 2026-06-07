import Contracts
import Application
import Domain
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimePackageReceiptStateReaderTests: XCTestCase {
    func testPkgInfoSuccessReportsReceiptPresent() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "ai.tirosh.vitalserver.helper",
            runProcess: { _, _ in RuntimeProcessResult(exitCode: 0, stdout: "package-id: ai.tirosh.vitalserver.helper\n", stderr: "") }
        )

        XCTAssertEqual(state, .present(identifier: "ai.tirosh.vitalserver.helper"))
    }

    func testExplicitNoReceiptReportsAbsent() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "ai.tirosh.vitalserver.helper",
            runProcess: { _, _ in
                RuntimeProcessResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "No receipt for 'ai.tirosh.vitalserver.helper' found at '/'.\n"
                )
            }
        )

        XCTAssertEqual(state, .absent(identifier: "ai.tirosh.vitalserver.helper"))
    }

    func testUnknownPkgInfoFailureReportsReadFailure() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "ai.tirosh.vitalserver.helper",
            runProcess: { _, _ in RuntimeProcessResult(exitCode: 2, stdout: "", stderr: "database locked\n") }
        )

        XCTAssertEqual(
            state,
            .readFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "exitCode=2 stderr=database locked")
        )
    }

    func testPkgInfoOutputIssueReportsReadFailure() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "ai.tirosh.vitalserver.helper",
            runProcess: { _, _ in
                RuntimeProcessResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "",
                    outputIssues: [
                        RuntimeCommandOutputIssue(stream: .stderr, message: "pkgutil stderr is not valid UTF-8"),
                    ]
                )
            }
        )

        XCTAssertEqual(
            state,
            .readFailed(
                identifier: "ai.tirosh.vitalserver.helper",
                reason: "exitCode=1 outputIssues=stderr:pkgutil stderr is not valid UTF-8"
            )
        )
    }

    func testPkgInfoExecutionIssueReportsReadFailure() {
        let state = RuntimePackageReceiptStateReader.state(
            identifier: "ai.tirosh.vitalserver.helper",
            runProcess: { _, _ in
                RuntimeProcessResult(
                    exitCode: 127,
                    stdout: "",
                    stderr: "",
                    executionIssue: RuntimeProcessExecutionIssue(
                        kind: .processLaunchFailed,
                        message: "pkgutil denied"
                    )
                )
            }
        )

        XCTAssertEqual(
            state,
            .readFailed(
                identifier: "ai.tirosh.vitalserver.helper",
                reason: "exitCode=127 executionIssue=processLaunchFailed: pkgutil denied"
            )
        )
    }
}
